#!/bin/bash
# Anbernic RG552 extras, installed while the boot partition is still mounted
# (build_kernel-rk3399.sh mounted it; finishing_touches.sh unmounts it).

echo -e "Installing the RG552 fan control, boot switch and Wi-Fi bits...\n\n"

# Fan: userspace owns it (the kernel thermal zones do not), see rg552-fan.
sudo install -D -m 0755 scripts/rg552/rg552-fan Arkbuild/usr/local/bin/rg552-fan
sudo cp scripts/rg552/rg552-fan.service Arkbuild/etc/systemd/system/rg552-fan.service
sudo mkdir -p Arkbuild/var/lib/rg552
echo auto | sudo tee Arkbuild/var/lib/rg552/fan-mode >/dev/null
sudo chroot Arkbuild/ bash -c "systemctl enable rg552-fan.service"

# Android / dArkMoss boot switch. spruce's "Boot to Android" app calls it.
sudo install -D -m 0755 scripts/rg552/rg552-bootswitch Arkbuild/usr/local/sbin/rg552-bootswitch

# A copy on the FAT partition, which any PC can read, for getting back into
# dArkMoss without Android's help.
sudo mkdir -p ${mountpoint}/rg552-bootswitch
sudo cp scripts/rg552/rg552-bootswitch ${mountpoint}/rg552-bootswitch/rg552-bootswitch.sh
cat <<'README' | sudo tee ${mountpoint}/rg552-bootswitch/README.txt >/dev/null
Switching the RG552 between dArkMoss (spruce) and Android
=========================================================

The RG552 boots this card (TF1) when it carries a boot loader, and Android
from its internal storage when it does not.

  dArkMoss -> Android:  spruce's "Boot to Android" app. It saves the start of
                        the boot loader into an unused area of this card,
                        blanks it, and reboots into Android.

  Android -> dArkMoss:  the "SpruceOS" Android app (Boot2SpruceOS.apk, from
                        github.com/MarsInsanity/Boot2SpruceOS; press A), which
                        needs root. It copies the saved loader back and
                        reboots into dArkMoss and spruce.

Without the Android app, from a Linux or macOS PC with this card in a reader
(replace /dev/sdX with the card itself, e.g. from lsblk / diskutil list):

  sudo sh rg552-bootswitch.sh status /dev/sdX
  sudo sh rg552-bootswitch.sh linux  /dev/sdX

Only the first 16 MiB of the card are ever read or written (the saved copies
in sectors 39-63, the loader from sector 64: every copy of U-Boot and trust);
no partition and no file is touched. The sector-*.bin files in this folder are
the same saved copies, as a last resort.
README

# Wi-Fi: the internal RTL8188FU (USB). The driver autoloads on its USB id;
# listing it as well covers the module being probed before udev settles.
echo rtl8188fu | sudo tee Arkbuild/etc/modules-load.d/rg552-wifi.conf >/dev/null

# exFAT spruce cards in TF2: this BSP kernel has no exFAT driver (AmberELEC's
# CONFIG_EXFAT_FS has nothing behind it here), so mount it through FUSE.
install_package 64 exfat-fuse
if [ ! -e Arkbuild/sbin/mount.exfat ] && [ ! -e Arkbuild/usr/sbin/mount.exfat ]; then
  sudo ln -sf mount.exfat-fuse Arkbuild/usr/sbin/mount.exfat
fi

# adbd only where there is a USB device controller: the Type-C port's DWC3 is
# dual-role (otg) in the RG552 dts, so there is one; without it (a kernel with
# the port host-only) adbd is skipped at once instead of its 10 s wait.
sudo mkdir -p Arkbuild/etc/systemd/system/adbd.service.d
printf '[Unit]\n# RG552: only when a USB device controller exists (the Type-C port in otg mode).\nConditionDirectoryNotEmpty=/sys/class/udc\n' \
  | sudo tee Arkbuild/etc/systemd/system/adbd.service.d/rg552-no-udc.conf >/dev/null

# Console font: Debian's default 8x16 is about 1 mm tall on the 5.36" 1920x1152
# panel, so tty1 (mount-spruce's messages, /boot/darkmoss-debug's boot text)
# uses Terminus Bold 16x32 instead: 120x36 characters. The cached copy
# console-setup.service loads at boot is rebuilt here; failing that, it rebuilds
# it itself on the first boot, this file being newer than the cache.
CONSOLE_SETUP=Arkbuild/etc/default/console-setup
if [ -f "$CONSOLE_SETUP" ]; then
  sudo sed -i -e 's/^FONTFACE=.*/FONTFACE="TerminusBold"/' -e 's/^FONTSIZE=.*/FONTSIZE="16x32"/' "$CONSOLE_SETUP"
else
  printf 'ACTIVE_CONSOLES="/dev/tty[1-6]"\nCHARMAP="UTF-8"\nCODESET="guess"\nFONTFACE="TerminusBold"\nFONTSIZE="16x32"\nVIDEOMODE=\n' \
    | sudo tee "$CONSOLE_SETUP" >/dev/null
fi
grep -q '^FONTFACE="TerminusBold"' "$CONSOLE_SETUP" && grep -q '^FONTSIZE="16x32"' "$CONSOLE_SETUP"
verify_action
sudo chroot Arkbuild/ bash -c "setupcon --save-only" || echo "setupcon --save-only failed; the font cache is rebuilt on the first boot"
