#!/bin/bash
# RK3399 (Anbernic RG552): create the MBR image and put the boot loader on it.
#
# The layout is the rk3326 one (setup_partition.sh): the loader in the raw
# area, p1 the FAT boot partition at sector 32768, p2 the rootfs, and firstboot
# adds SPRUCEOS as p3. The loader chain is the one ROCKNIX boots the RG552 with
# while Android stays on the eMMC:
#
#   sector    64  idbloader.img  Rockchip DDR init + miniloader (rkbin)
#   sector 16384  uboot.img      mainline U-Boot (evb-rk3399), loaderimage-packed
#   sector 24576  trust.img      Rockchip BL31 (rkbin), no BL32
#
# U-Boot then finds /extlinux/extlinux.conf on p1 by itself (distro boot).
# rg552-bootswitch (scripts/rg552) finds every idbloader, U-Boot and trust copy
# from these offsets (on the 512 KiB grid up to sector 32768), blanks each one's
# first sector to hand the next boot to Android, and puts them back.

echo -e "Setup the Image file...\n\n"

iName=$(echo ${UNIT} | tr '[:lower:]' '[:upper:]')
DISK="dArkMoss_${iName}_${DEBIAN_CODE_NAME}_${BUILD_DATE}.img"
dd if=/dev/zero of="${DISK}" bs=1M count=0 seek="${DISK_SIZE}" conv=fsync
parted -s "${DISK}" mklabel msdos
parted -s "${DISK}" -a min unit s mkpart primary fat32 ${SYSTEM_PART_START} ${SYSTEM_PART_END}
parted -s "${DISK}" set 1 boot on
parted -s "${DISK}" -a min unit s mkpart primary ${ROOT_FILESYSTEM_FORMAT} ${STORAGE_PART_START} ${STORAGE_PART_END}
# A fixed disk identifier: the kernel finds its root as PARTUUID=<id>-02, and
# that has to stay true across in-place updates, which rewrite extlinux.conf
# but never the partition table. (The 4.4 kernel's mmcblk numbering follows
# card detection order, so /dev/mmcblkNp2 is not stable with two SD slots.)
RG552_DISK_ID=0x52473552
sudo sfdisk --disk-id "${DISK}" ${RG552_DISK_ID}
verify_action
sync

# --- boot loader -------------------------------------------------------------
UBOOT_TAG=v2025.10
RKBIN_SHA=3e288fe814e059dd06833495f845cab04ac20a5c
RKBIN_URL=https://github.com/rockchip-linux/rkbin/raw/${RKBIN_SHA}

# Mainline U-Boot wants a current cross compiler; the Linaro 6.3 one utils.sh
# puts first in PATH is for the 4.4 kernel only.
for NEEDED_TOOL in gcc-aarch64-linux-gnu python3-pyelftools python3-setuptools python3-dev swig libgnutls28-dev uuid-dev libssl-dev bison flex bc
do
  if ! dpkg -s ${NEEDED_TOOL} &>/dev/null; then
    sudo apt -y update
    sudo apt -y install ${NEEDED_TOOL}
    verify_action
  fi
done
UBOOT_CROSS=/usr/bin/aarch64-linux-gnu-

rm -rf u-boot-rk3399 rkbin-rk3399
git clone --depth=1 -b ${UBOOT_TAG} https://github.com/u-boot/u-boot.git u-boot-rk3399
verify_action

mkdir -p rkbin-rk3399/bin/rk33 rkbin-rk3399/tools rkbin-rk3399/RKTRUST
for f in bin/rk33/rk3399_ddr_933MHz_v1.30.bin bin/rk33/rk3399_miniloader_v1.30.bin \
         bin/rk33/rk3399_bl31_v1.36.elf bin/rk33/rk3399_bl32_v2.12.bin \
         RKTRUST/RK3399TRUST.ini tools/loaderimage tools/trust_merger
do
  get_file -O rkbin-rk3399/${f} ${RKBIN_URL}/${f}
  if [ ! -s rkbin-rk3399/${f} ]; then
    echo "ERROR: could not fetch rkbin ${f}"
    exit 1
  fi
done
chmod +x rkbin-rk3399/tools/*

cd u-boot-rk3399
# As ROCKNIX's RK3399 build: no EFI loader. And no boot delay, there is no
# console on this handheld to interrupt it from.
echo "# CONFIG_EFI_LOADER is not set" >> configs/evb-rk3399_defconfig
echo "CONFIG_BOOTDELAY=0" >> configs/evb-rk3399_defconfig
# /boot/darkmoss-debug (README-logging.txt on /boot): kernel and systemd text
# on the panel, as the other units' boot.ini does it. extlinux.conf's APPEND
# ends in ${dm_debug}, which U-Boot expands (pxe_utils); mmc 1 is TF1 here.
echo 'CONFIG_USE_PREBOOT=y' >> configs/evb-rk3399_defconfig
echo 'CONFIG_PREBOOT="setenv dm_debug; if test -e mmc 1:1 /darkmoss-debug; then setenv dm_debug console=tty0 loglevel=7 systemd.show_status=1 darkmoss.debug; fi"' >> configs/evb-rk3399_defconfig
make ARCH=arm CROSS_COMPILE=${UBOOT_CROSS} evb-rk3399_defconfig
verify_action
make ARCH=arm CROSS_COMPILE=${UBOOT_CROSS} BL31=../rkbin-rk3399/bin/rk33/rk3399_bl31_v1.36.elf \
  BINMAN_ALLOW_MISSING=1 -j$(nproc)
if [ ! -s u-boot-dtb.bin ]; then
  echo "ERROR: U-Boot did not build u-boot-dtb.bin"
  exit 1
fi

# idbloader: DDR init and the miniloader, which loads uboot.img and trust.img.
./tools/mkimage -n rk3399 -T rksd \
  -d ../rkbin-rk3399/bin/rk33/rk3399_ddr_933MHz_v1.30.bin:../rkbin-rk3399/bin/rk33/rk3399_miniloader_v1.30.bin \
  idbloader.img
verify_action
../rkbin-rk3399/tools/loaderimage --pack --uboot u-boot-dtb.bin uboot.img 0x00200000
verify_action
cd ../rkbin-rk3399
./tools/trust_merger --ignore-bl32 --prepath ./ RKTRUST/RK3399TRUST.ini
verify_action
mv trust.img ../u-boot-rk3399/
cd ../u-boot-rk3399

for part in idbloader.img:64:16384 uboot.img:16384:24576 trust.img:24576:${SYSTEM_PART_START}; do
  IFS=: read -r img start end <<< "$part"
  size=$(stat -c %s $img)
  if [ $(( (size + 511) / 512 )) -gt $(( end - start )) ]; then
    echo "ERROR: $img ($size bytes) does not fit between sectors $start and $end"
    exit 1
  fi
  dd if=$img of="../${DISK}" bs=512 seek=$start conv=sync,noerror,notrunc
done
cd ..
rm -rf u-boot-rk3399 rkbin-rk3399
