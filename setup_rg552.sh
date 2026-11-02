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

  Android -> dArkMoss:  the "RG552 Boot Switch" Android app ("Boot dArkMoss"),
                        which needs root. It copies the saved loader back and
                        reboots into dArkMoss.

Without the Android app, from a Linux or macOS PC with this card in a reader
(replace /dev/sdX with the card itself, e.g. from lsblk / diskutil list):

  sudo sh rg552-bootswitch.sh status /dev/sdX
  sudo sh rg552-bootswitch.sh linux  /dev/sdX

Only sectors 39-42, 64, 16384 and 24576 at the start of the card are ever
read or written; no partition and no file is touched. The sector-*.bin files
in this folder are the same saved copies, as a last resort.
README

# Wi-Fi: the internal RTL8188FU (USB). The driver autoloads on its USB id;
# listing it as well covers the module being probed before udev settles.
echo rtl8188fu | sudo tee Arkbuild/etc/modules-load.d/rg552-wifi.conf >/dev/null
