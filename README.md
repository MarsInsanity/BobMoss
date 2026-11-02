# <p align="center">Welcome to dArkOS</p>

### <p align="center">Debian based version of the ArkOS operating system for select RK3326 and RK3566 based portable gaming devices.</p>

[![Donate](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://www.paypal.com/donate?hosted_button_id=RC72LJ4SSERSU)

The overarching goals of dArkOS is as follows:
1. Highly customizable 
1. Performance
1. Online Updates (Won't require SD card reflashing unless there are major structural changes like file system changes.)
1. Enthusiats focused

This is intended to continue the work from [ArkOS](https://github.com/christianhaitian/arkos/wiki) but in a way that allows others to easily fork and modify the OS to their own taste.  If there's a feature not currently available that you want, you can fork this and add it yourself.
Don't feel like building the OS from scratch or don't have the resources to do so?  Ok, just download one of the available prebuilt images and make changes right in the OS.  Since this OS is based on the latest stable version of Debian, you have
access to over 64,000 packages you can install via the Debian Advanced Package Tool (APT).  Want to build the latest testing or bleeding edge release of Debian? See the notes below on how to accomplish this.

**Building instructions:**
   - Suggested Environment - Ubuntu or related variants, version 24.04 or newer.  Windows Subsystem for Linux (WSL) is not supported and will not work due to no support for chroot. \
     Because chroot is used in this process, heavy use of sudo is made.  To reduce the possibility of priviledge issues, \
     it's best to be able to execute sudo without needing a password.  This can be done using one of the 2 methods below.
      - Method 1: - Open a Terminal window and type `sudo visudo` \
                    In the bottom of the file, add the following line: `$USER ALL=(ALL) NOPASSWD: ALL` \
                    Where $USER is your username on your system. Save and close the sudoers file (if you haven't changed your \
                    default terminal editor (you'll know if you have), press Ctl + x to exit nano and it'll prompt you to save).
      - Method 2: - Clone this git repo then run `./FreeSudo.sh`.  If there were no errors, it should've completed this change for you. \
                    You can verify this by checking if a `/etc/sudoers.d/$USER` file exists and contains `$USER ALL=(ALL) NOPASSWD: ALL` in it.
     
Now you should be able to just run make <device_name> to build for a supported device.  Example: `make rg353m`

**Notes**
- To build on a different release of Debian, change the DEBIAN_CODE_NAME export in the Makefile or add DEBIAN_CODE_NAME=<release> as a variable to `make`.  Other debian code names can be found at https://www.debian.org/releases/
- By default, this will build with both a 64bit and 32bit userspace.  This is primarily to support some 32bit ports available through PortMaster.  There are also some 32bit retroarch emulators available but the performance seems to be similar to the 64bit retroarch emulators at this point.
 - To build without 32bit support, change the BUILD_ARMHF export in the Makefile to n or add BUILD_ARMHF=n as a variable to `make`.
- For RK3566, you can add Kodi to your build.  Just change the BUILD_KODI export in the Makefile to y or add BUILD_KODI=y as a variavble to `make`.  Kodi is also available as a prepackaged build in the extra_packages/rk3566 subfolder.  Just copy it to your tools folder and launch from Options/Tools in the start menu.
 - Be aware that building Kodi will add a significant amount of time to your build.  Could be double or triple the build time.
- Initial build time on an Intel I7-8700 65w unit with a 512GB NVME SSD and 32GB of DDR4 memory is a little over 19 hours.  Subsequent builds are about 3 hours thanks to ccache.

# Credits and Thanks
[ChatGPT](https://chatgpt.com/) for guidance on how to build a Debian image \
Jetup13 for many themes \
dani7959 for the replica theme \
pix33l for the pixui theme \
TheGreatCrippler for testing and feedback \
kloptops for testing and feedback \
Fraxinus88 for testing and feedback \
ImCoKeMaN for testing and feedback \
[PortMaster](https://portmaster.games/) team for support in figuring out PM interface issues



test webhook.... again......again!

## dArkMoss

dArkMoss is spruceUI's fork of dArkOS: a Debian base OS on TF1 that hands off to
[spruce](https://github.com/spruceUI/spruceOS) on TF2. The emulator and
EmulationStation builds are stripped from the unit build scripts because spruce
provides all of that from its own card; what is left is debootstrap, the kernel
and image assembly.

Units:

| unit | device | Makefile target | script |
|---|---|---|---|
| rgb30 | Powkiddy RGB30 | `make rgb30` | `build_rgb30.sh` |
| miniloong | Miniloong Pocket 1 | `make miniloong` | `build_miniloong.sh` |
| a10mini | A10 Mini (RK3326) | `make a10mini` | `build_a10mini.sh` |
| g350 | G350 (RK3326) | `make g350` | `build_g350.sh` |
| v10 | Powkiddy V10 (RK3326) | `make v10` | `build_v10.sh` |
| xumini | MagicX XU Mini M (RK3326) | `make xumini` | `build_xumini.sh` |
| rg552 | Anbernic RG552 (RK3399) | `make rg552` | `build_rg552.sh` |

Images are built on GitHub Actions, not locally. Under Actions:

- **build-all** takes a version (`v1.2.3`) and optionally a list of units
  (blank = every unit in `.github/units.txt`), builds them in parallel and
  publishes them as the `beta-<branch>` prerelease. A beta never becomes the
  latest release, so spruce devices and the installer do not see it.
- **create-latest-release** turns a beta into a draft release tagged with its
  version. It refuses a beta that is missing any unit. Publish the draft by
  hand from the Releases page.

Images ship as `dArkMoss_<UNIT>_<suite>_<date>.img.7z.001`
and `.002` because a single volume is over GitHub's asset limit; the parts are
a plain byte split, so `cat` them (or let 7z read `.001`) to extract.

Beside each image the build also produces `dArkMoss_<UNIT>_<version>.dmupd`, an
update payload spruce's Firmware Update app downloads and applies in place: the
boot partition files, every rootfs file the dArkMoss build added or changed
(chosen by the dpkg database, see `build_update.sh`) and the U-Boot
resource partition (dtb, charging animation, power-on logo), with the applier
`scripts/spruce/dmupd-apply.sh` inside. A release carries a `SHA256SUMS` over
all of its assets, which the app checks the download against. The app only
reads the latest release, so betas are never offered as updates.

Adding a unit that dArkOS already supports: copy `build_rgb30.sh` (rk3566) or
`build_g350.sh` (rk3326) to `build_<unit>.sh` and change `UNIT`. On rk3566 add
`logos/unrotated/dArkMoss<unit>.png` (the kernel boot logo); rk3326 units share
`logos/unrotated/dArkMoss.bmp` (the U-Boot logo on the boot partition). Give it
a name in the `HW_DEVICE` and `SPRUCE_PLATFORM` cases in
`setup_spruce_handoff.sh` and in `build_update.sh`, and add the unit to
`.github/units.txt`. Everything else in the pipeline already keys on `UNIT`.

### Anbernic RG552 (RK3399)

The RG552 is the only RK3399 unit, so it has its own kernel, loader and image
scripts (`build_kernel-rk3399.sh`, `image_setup-rk3399.sh`) and otherwise
follows the rk3326 units: MBR card, FAT `/boot` + btrfs rootfs, Rockchip 4.4
BSP kernel, the Mali blob (here Mali-T860, `libmali-midgard-t86x-r18p0-gbm`)
and the RGA-rotated SDL2 from `rk3326_core_builds` (`CORE_BUILDS_CHIPSET` in
`utils.sh`).

- **Kernel**: AmberELEC's `kernel_rg552` (pinned) with AmberELEC's RG552 config
  and patches, plus `patches/rg552/kernel/`: GT927 touch through the in-tree
  goodix driver (with `touchscreen-inverted-x/-y` support), the fan taken off
  the thermal zones, the USB Wi-Fi rails kept on, stable mmc aliases.
- **Wi-Fi**: the internal RTL8188FU (USB) through kelebek333's out-of-tree
  driver, built against that kernel. There is no Bluetooth radio.
- **Boot**: Rockchip DDR init + miniloader, mainline U-Boot (`evb-rk3399`) and
  rkbin's BL31, reading `/extlinux/extlinux.conf`. The root is found by
  `PARTUUID=52473552-02`; the disk id is fixed at build time so in-place updates
  keep booting. No initramfs.
- **Fan**: `rg552-fan` (`scripts/rg552/`), a userspace loop with an Auto curve
  and fixed High/Medium/Low/Off speeds, always full speed at 85 C. spruce's Fan
  Control app drives it with `rg552-fan set <mode>`.
- **Android**: Android stays on the eMMC. `rg552-bootswitch android` (spruce's
  Boot to Android app) saves the first sector of each loader stage into the
  unused sectors 40-42 of TF1 and blanks them, so the next boot falls through to
  Android; `rg552-bootswitch linux` copies them back. The Android side is the
  "RG552 Boot Switch" app in `android/rg552-bootswitch/` (needs root), and the
  same script is on the card's FAT partition for recovery from a PC.
