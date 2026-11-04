#!/bin/bash
# Build RG552BootSwitch.apk (the "SpruceOS" app) with the bare Android SDK
# tools (no Gradle): aapt2, javac, d8, zipalign, apksigner. Needs ANDROID_HOME
# (or ANDROID_SDK_ROOT) with build-tools and a platform of API 33 or later
# (the icon's monochrome layer) installed, and a JDK.
#
#   ./build.sh [OUTPUT.apk]
#
# Signs with $KEYSTORE (password $KEYSTORE_PASS, alias $KEY_ALIAS) when set,
# otherwise with a throwaway key generated here.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT_APK="${1:-$HERE/RG552BootSwitch.apk}"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[ -n "$SDK" ] && [ -d "$SDK" ] || { echo "ANDROID_HOME is not set" >&2; exit 1; }
BT="$(ls -d "$SDK"/build-tools/* | sort -V | tail -n 1)"
# The newest released platform: not an extension (android-35-ext14) or a beta (android-37.2-beta1).
PLATFORM_DIR="$(ls -d "$SDK"/platforms/android-* | { grep -E '/android-[0-9]+(\.[0-9]+)?$' || true; } | sort -V | tail -n 1)"
PLATFORM_JAR="${PLATFORM_DIR:-$(ls -d "$SDK"/platforms/android-* | sort -V | tail -n 1)}/android.jar"
[ -x "$BT/aapt2" ] && [ -f "$PLATFORM_JAR" ] || { echo "no build-tools/platform in $SDK" >&2; exit 1; }
PLATFORM_API="$(basename "$(dirname "$PLATFORM_JAR")" | grep -o '[0-9]\+' | head -n 1)"
[ "${PLATFORM_API:-0}" -ge 33 ] || { echo "need an Android platform of API 33 or later, found $PLATFORM_JAR" >&2; exit 1; }
VERSION_NAME="${VERSION_NAME:-1.0}"
VERSION_CODE="${VERSION_CODE:-1}"

BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

# The script is the one dArkMoss ships (scripts/rg552), bundled as an asset,
# next to spruce's font (assets/fonts).
mkdir -p "$BUILD/assets" "$BUILD/classes" "$BUILD/dex" "$BUILD/gen"
cp -r "$HERE/assets/." "$BUILD/assets/"
cp "$HERE/../../scripts/rg552/rg552-bootswitch" "$BUILD/assets/rg552-bootswitch.sh"

"$BT/aapt2" compile --dir "$HERE/res" -o "$BUILD/res.zip"
"$BT/aapt2" link -o "$BUILD/base.apk" -I "$PLATFORM_JAR" \
  --manifest "$HERE/AndroidManifest.xml" -R "$BUILD/res.zip" -A "$BUILD/assets" \
  --java "$BUILD/gen" --auto-add-overlay \
  --min-sdk-version 21 --target-sdk-version 29 \
  --version-code "$VERSION_CODE" --version-name "$VERSION_NAME"

javac -source 8 -target 8 -encoding UTF-8 -Xlint:-options \
  -classpath "$PLATFORM_JAR" -d "$BUILD/classes" \
  $(find "$HERE/src" "$BUILD/gen" -name '*.java')
"$BT/d8" --release --min-api 21 --lib "$PLATFORM_JAR" --output "$BUILD/dex" \
  $(find "$BUILD/classes" -name '*.class')

cp "$BUILD/base.apk" "$BUILD/unsigned.apk"
(cd "$BUILD/dex" && zip -q -j "$BUILD/unsigned.apk" classes.dex)
"$BT/zipalign" -f -p 4 "$BUILD/unsigned.apk" "$BUILD/aligned.apk"

if [ -z "${KEYSTORE:-}" ]; then
  KEYSTORE="$BUILD/throwaway.keystore"; KEYSTORE_PASS=android; KEY_ALIAS=rg552
  keytool -genkeypair -keystore "$KEYSTORE" -storepass "$KEYSTORE_PASS" -keypass "$KEYSTORE_PASS" \
    -alias "$KEY_ALIAS" -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=dArkMoss RG552" >/dev/null 2>&1
fi
"$BT/apksigner" sign --ks "$KEYSTORE" --ks-pass "pass:$KEYSTORE_PASS" --ks-key-alias "${KEY_ALIAS:-rg552}" \
  --out "$OUT_APK" "$BUILD/aligned.apk"
"$BT/apksigner" verify "$OUT_APK"
echo "Built $OUT_APK"
