#!/bin/sh
# dArkMoss: switch the OTG port between host mode (a WiFi dongle) and wired adbd.
#
# On the R36S clone the only USB data port is the RK3326 OTG controller, and
# adbd binds it as a USB gadget, after which nothing plugged in is seen. The
# choice is whether adbd.service starts at boot: disabled leaves the port a
# host for a dongle, enabled gives wired adb while nothing is plugged in at
# power-on (adbd-gadget.sh skips it otherwise).

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

APP_DIR="$(dirname "$0")"
CONFIG="$APP_DIR/config.json"

set_label() {
    jq --arg l "$1" '.label = $l' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
}

start_pyui_message_writer 1

if [ ! -f /etc/systemd/system/adbd.service ]; then
    log_and_display_message "This dArkMoss image has no adbd service. Press A to close."
    acknowledge
    exit 1
fi

if systemctl is-enabled --quiet adbd; then
    log_and_display_message "The USB port is in ADB mode: wired adb, no WiFi dongle.\n\nSwitch to WiFi dongle mode?\n\nA: switch   B: cancel"
    confirm || exit 0
    systemctl disable adbd >/dev/null 2>&1
    systemctl stop adbd >/dev/null 2>&1
    set_label "USB Mode: WiFi dongle"
    log_and_display_message "WiFi dongle mode is on.\n\nPlug the dongle into the OTG port. If it is not found, restart the device.\n\nPress A to close."
else
    log_and_display_message "The USB port is in WiFi dongle mode.\n\nSwitch to ADB mode? Unplug the dongle first; WiFi stops until you switch back.\n\nA: switch   B: cancel"
    confirm || exit 0
    systemctl enable adbd >/dev/null 2>&1
    set_label "USB Mode: ADB"
    if systemctl start adbd >/dev/null 2>&1 && systemctl is-active --quiet adbd; then
        log_and_display_message "ADB mode is on.\n\nConnect the OTG port to your computer and run: adb shell\n\nPress A to close."
    else
        log_and_display_message "ADB mode is set, but adbd did not start: something is still plugged into the OTG port.\n\nUnplug it and restart the device.\n\nPress A to close."
    fi
fi
acknowledge
