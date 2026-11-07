# SpruceOS (Android app for the RG552)

The Android half of switching the Anbernic RG552 between Android (eMMC) and
dArkMoss/spruce (TF1 card). It used to be called "RG552 Boot Switch"; the
package name is unchanged, so it replaces that app.

- **dArkMoss → Android**: spruce's *Boot to Android* app runs
  `rg552-bootswitch android`. It saves the first sector of each boot loader
  stage on the TF1 card into its unused sectors 40-42 (marker in 39), blanks
  them, and reboots. With no loader on TF1, the RG552 starts Android.
- **Android → dArkMoss**: this app runs the same script
  (`scripts/rg552/rg552-bootswitch`, bundled as an asset) with `linux`, which
  copies the saved sectors back, then reboots.

## Using it

One screen, made for the controller and laid out like spruce's own (spruce's
tree, font and theme colours):

- *...Checking if SpruceOS can be booted into*: it reads the TF1 card.
- *Press the A button to boot into SpruceOS*: A puts the loader back and
  reboots into dArkMoss and spruce.
- *dArkMoss is not bootable, ...*: no dArkMoss card with a saved loader in TF1.
  Insert one and press A to scan again (coming back to the app scans too).

B or Back leaves. A tap anywhere does what A does. If the RG552's A button
does nothing, `adb logcat -s SpruceOS` shows each key's code and scan code.

The app needs **root** (the firmware's su, or Magisk) because it writes raw
sectors of the SD card. Without root, the same can be done with
`adb root` + `adb shell sh rg552-bootswitch.sh linux`, or from a Linux/macOS PC
with the card in a reader: see `rg552-bootswitch/README.txt` on the card's
BOOT partition.

## Icon

spruce's tree (spruceOS `spruce/imgs/tree_sm_close_crop.png`), traced to
straight edges by `tools/make-icons.py`, which writes:

- `res/mipmap-*/ic_launcher.png`: the round icon Android 7.1 (the RG552's own
  Android) and older use;
- `res/drawable/ic_launcher_foreground.xml`: the adaptive icon's foreground
  (Android 8+) and its monochrome layer, which Android 13+ tints to the
  wallpaper's colours when themed icons are on. The tree is 48 dp tall on the
  108 dp canvas, inside the 66 dp circle every launcher mask keeps.

The font is spruce's theme font (`Themes/SPRUCE/nunwen.ttf`, merged Nunito,
SIL Open Font License: `assets/fonts/OFL.txt`), cut down to Latin characters.

## Building

GitHub Actions builds it (`build-rg552-android` workflow; the APK is an
artifact, and can be attached to a release by tag). Locally, with an Android
SDK (a platform of API 33 or later) and a JDK:

    ANDROID_HOME=~/Android/Sdk android/rg552-bootswitch/build.sh

No Gradle: `build.sh` drives aapt2, javac, d8, zipalign and apksigner directly.
Set `KEYSTORE`, `KEYSTORE_PASS` and `KEY_ALIAS` to sign with your own key;
otherwise a throwaway key is generated, so an update built elsewhere has to be
installed over an uninstall.

## Signing key (so updates install over the previous app)

Android only installs an update over an app signed with the same key. The
workflow signs with the keystore in the repository secret `RG552_APK_KEYSTORE`
(base64), password `RG552_APK_KEYSTORE_PASS`, alias `RG552_APK_KEY_ALIAS`
(optional, default `rg552`); without the secret it falls back to a throwaway
key and warns. To create it once, on any PC with a JDK and the GitHub CLI:

    keytool -genkeypair -keystore rg552.keystore -alias rg552 -keyalg RSA \
      -keysize 2048 -validity 10000 -dname "CN=dArkMoss RG552"
    base64 -w0 rg552.keystore | gh secret set RG552_APK_KEYSTORE -R MarsInsanity/BobMoss
    gh secret set RG552_APK_KEYSTORE_PASS -R MarsInsanity/BobMoss

(keytool asks for the password; give the same one to the second `gh secret
set`.) Keep `rg552.keystore` somewhere safe: an app signed with a different
key cannot update this one. The first build signed with it still needs the old
app uninstalled once. Version codes are minutes since the epoch, so every
build is newer than the last.
