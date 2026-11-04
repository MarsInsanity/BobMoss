#!/bin/bash
# RK3399 (Anbernic RG552) kernel, Wi-Fi module and boot partition.
#
# The kernel is AmberELEC's RG552 tree: Rockchip's 4.4 BSP, the same family as
# the rk3326 units' kernel, so the Mali blob, RGA2 (for the rotated SDL) and the
# singleadc joypad all work the way the rest of dArkMoss expects. It is pinned,
# along with the AmberELEC config and patches that go with it. On top of that:
#
#   patches/rg552/kernel/0001  dts: GT927 touch on the in-tree goodix driver,
#                              fan handed to userspace, USB Wi-Fi rails on,
#                              SDIO Wi-Fi/BT platdata off, stable mmc aliases
#   patches/rg552/kernel/0002  goodix: touchscreen-inverted-x/-y
#   patches/rg552/kernel/0003  goodix: reset-gpios/irq-gpios (mainline 4.5's
#                              reset at probe), DT size on an empty config
#   patches/rg552/kernel/0004  singleadc joypad: optional ADC key (the F key
#                              on SARADC 1) reported on the pad
#
# The internal Wi-Fi is an RTL8188FU on USB, which this kernel has no driver
# for, so kelebek333's out-of-tree one is built against it (as AmberELEC does).

KERNEL_SRC="kernel_rg552"
KERNEL_SHA="0c15ff851c1d24fac588bd4427bb45b9ab88f452"
KERNEL_REPO="https://github.com/AmberELEC/kernel_rg552.git"
AMBERELEC_SHA="108db43ddd6d4e3c6f9d68da8ed03b49ef151aa0"
AMBERELEC_RAW="https://raw.githubusercontent.com/AmberELEC/AmberELEC/${AMBERELEC_SHA}"
RTL8188FU_SHA="c8c95708b3756c67139c456a2a6576c1e6491d82"
KERNEL_DTB="rk3399-rg552-linux.dtb"
SCREEN_ROTATION="3"

if [ ! -d "$KERNEL_SRC" ]; then
  mkdir -p $KERNEL_SRC
  git -C $KERNEL_SRC init -q
  git -C $KERNEL_SRC remote add origin $KERNEL_REPO
  git -C $KERNEL_SRC fetch --depth=1 origin $KERNEL_SHA
  verify_action
  git -C $KERNEL_SRC checkout -q FETCH_HEAD
  verify_action
fi

cd $KERNEL_SRC
# AmberELEC's RG552 kernel patches, then ours.
for p in es8316.patch mmc.patch; do
  get_file -O ../amberelec-${p} ${AMBERELEC_RAW}/projects/Rockchip/packages/linux/patches/RG552/${p}
  git apply -R --check ../amberelec-${p} 2>/dev/null && continue
  git apply ../amberelec-${p}
  verify_action
done
rm -f ../amberelec-*.patch
for patch in ../patches/rg552/kernel/*.patch; do
  git apply -R --check "$patch" 2>/dev/null && continue
  if ! git apply "$patch"; then
    echo "ERROR: $patch did not apply."
    exit 1
  fi
done

# AmberELEC's config, adjusted for a Debian/systemd rootfs on btrfs.
get_file -O .config ${AMBERELEC_RAW}/projects/Rockchip/devices/RG552/linux/linux.aarch64.conf
if [ ! -s .config ]; then
  echo "ERROR: could not fetch the RG552 kernel config."
  exit 1
fi
scripts/config --set-str DEFAULT_HOSTNAME "rg552"
scripts/config --set-str INITRAMFS_SOURCE ""
# The rootfs, booted without an initramfs (as the V10 is).
scripts/config --enable BTRFS_FS --enable BTRFS_FS_POSIX_ACL
# systemd
scripts/config --enable AUTOFS4_FS --enable CGROUP_PIDS --enable BPF_SYSCALL
# The GT927 through the in-tree goodix driver (see patches/rg552/kernel).
scripts/config --enable TOUCHSCREEN_GOODIX
# FunctionFS for adbd's USB gadget, and the mass storage gadget.
scripts/config --enable USB_CONFIGFS_F_FS --enable USB_CONFIGFS_MASS_STORAGE
# No SDIO Wi-Fi on the RG552 (its Wi-Fi is the USB RTL8188FU). The built-in
# Broadcom AP6xxx driver finds no chip at boot and then "removes" the card on
# the SDIO host, which here is TF2: the spruce card vanished ~5 s into every
# boot (rfkill-wlan -> mmc_host_rescan -> dw_mci_set_sdio_status(0)).
scripts/config --disable AP6XXX
make ARCH=arm64 olddefconfig
for opt in BTRFS_FS TOUCHSCREEN_GOODIX AUTOFS4_FS; do
  if ! grep -q "^CONFIG_${opt}=y" .config; then
    echo "ERROR: CONFIG_${opt} did not stick in the RG552 kernel config."
    exit 1
  fi
done
CFLAGS=-Wno-deprecated-declarations make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules_prepare
CFLAGS=-Wno-deprecated-declarations make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image modules rockchip/${KERNEL_DTB}
verify_action
cd ..

# Install kernel modules
sudo make -C $KERNEL_SRC ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH=../Arkbuild modules_install
KERNEL_VERSION=$(basename $(find Arkbuild/lib/modules -maxdepth 1 -mindepth 1 -type d | head -n 1))

# --- internal Wi-Fi: RTL8188FU (USB) ----------------------------------------
rm -rf rtl8188fu
git clone https://github.com/kelebek333/rtl8188fu.git rtl8188fu
verify_action
git -C rtl8188fu checkout -q ${RTL8188FU_SHA}
verify_action
get_file -O rtl8188fu-fix_build.patch ${AMBERELEC_RAW}/projects/Rockchip/packages/RTL8188FU/patches/fix_build.patch
(cd rtl8188fu && git apply ../rtl8188fu-fix_build.patch)
verify_action
rm -f rtl8188fu-fix_build.patch
make -C rtl8188fu -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
  KSRC=$PWD/$KERNEL_SRC KVER=${KERNEL_VERSION} CONFIG_POWER_SAVING=n \
  KCFLAGS="-Wno-address" modules
verify_action
sudo mkdir -p Arkbuild/lib/modules/${KERNEL_VERSION}/extra
sudo cp rtl8188fu/*.ko Arkbuild/lib/modules/${KERNEL_VERSION}/extra/
if ls rtl8188fu/firmware/*.bin &>/dev/null; then
  sudo mkdir -p Arkbuild/lib/firmware/rtlwifi
  sudo cp rtl8188fu/firmware/*.bin Arkbuild/lib/firmware/rtlwifi/
fi
# The driver's own advice: no USB selective suspend and no power management,
# both of which drop the link on this chip.
echo "options rtl8188fu rtw_power_mgnt=0 rtw_enusbss=0 rtw_ips_mode=0" | \
  sudo tee Arkbuild/etc/modprobe.d/rtl8188fu.conf
rm -rf rtl8188fu
sudo touch Arkbuild/lib/modules/${KERNEL_VERSION}/modules.builtin.modinfo
sudo cp /usr/bin/qemu-aarch64-static Arkbuild/usr/bin/
call_chroot "depmod ${KERNEL_VERSION}"
sudo rm -f Arkbuild/usr/bin/qemu-aarch64-static

# --- boot partition -----------------------------------------------------------
BOOT_PART_OFFSET=$((SYSTEM_PART_START * 512))
BOOT_PART_SIZE=$(( (SYSTEM_PART_END - SYSTEM_PART_START + 1) * 512 ))
LOOP_BOOT=$(sudo losetup --find --show --offset ${BOOT_PART_OFFSET} --sizelimit ${BOOT_PART_SIZE} ${DISK})
sudo mkfs.vfat -F 32 -n BOOT ${LOOP_BOOT}
mountpoint="mnt/boot"
mkdir -p ${mountpoint}
sudo mount ${LOOP_BOOT} ${mountpoint}

sudo cp $KERNEL_SRC/.config Arkbuild/boot/config-${KERNEL_VERSION}
sudo cp $KERNEL_SRC/arch/arm64/boot/Image ${mountpoint}/
sudo cp $KERNEL_SRC/arch/arm64/boot/dts/rockchip/${KERNEL_DTB} ${mountpoint}/

# U-Boot's distro boot reads this. No initramfs: btrfs and the SD host are
# built in. The root is found by PARTUUID (image_setup-rk3399.sh fixes the disk
# id), so it does not matter which slot the kernel enumerates first.
sudo mkdir -p ${mountpoint}/extlinux
cat <<EOF | sudo tee ${mountpoint}/extlinux/extlinux.conf
# dArkMoss for the Anbernic RG552. Rewritten by updates.
TIMEOUT 0
DEFAULT dArkMoss

LABEL dArkMoss
  LINUX /Image
  FDT /${KERNEL_DTB}
  APPEND root=PARTUUID=52473552-02 rootfstype=btrfs rootwait rw fsck.repair=yes net.ifnames=0 fbcon=rotate:${SCREEN_ROTATION} console=ttyFIQ0 quiet splash consoleblank=0 vt.global_cursor_default=0 loglevel=3 panic=10 \${dm_debug}
EOF

rm -rf $KERNEL_SRC
