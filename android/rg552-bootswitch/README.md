# RG552 Boot Switch (Android)

The Android half of switching the Anbernic RG552 between Android (eMMC) and
dArkMoss/spruce (TF1 card).

- **dArkMoss → Android**: spruce's *Boot to Android* app runs
  `rg552-bootswitch android`. It saves the first sector of each boot loader
  stage on the TF1 card into its unused sectors 40-42 (marker in 39), blanks
  them, and reboots. With no loader on TF1, the RG552 starts Android.
- **Android → dArkMoss**: this app runs the same script
  (`scripts/rg552/rg552-bootswitch`, bundled as an asset) with `linux`, which
  copies the saved sectors back, then reboots.

The app needs **root** (Magisk, or the firmware's su) because it writes raw
sectors of the SD card. Without root, the same can be done with
`adb root` + `adb shell sh rg552-bootswitch.sh linux`, or from a Linux/macOS PC
with the card in a reader: see `rg552-bootswitch/README.txt` on the card's
BOOT partition.

## Building

GitHub Actions builds it (`build-rg552-android` workflow; the APK is an
artifact, and can be attached to a release by tag). Locally, with an Android
SDK and a JDK:

    ANDROID_HOME=~/Android/Sdk android/rg552-bootswitch/build.sh

No Gradle: `build.sh` drives aapt2, javac, d8, zipalign and apksigner directly.
Set `KEYSTORE`, `KEYSTORE_PASS` and `KEY_ALIAS` to sign with your own key;
otherwise a throwaway key is generated, so an update built elsewhere has to be
installed over an uninstall.
