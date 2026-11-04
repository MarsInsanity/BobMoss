#!/bin/bash

CARD=0
isitminiloong=""

# RGB30 (and the RGB20SX, which runs its image): this card's path names are
# swapped - HP is the speaker, SPK the headphones (see spktoggle.sh) - and the
# udev rule runs this on every extcon change, charger and HDMI included, so the
# switch below would mute the speaker whenever a charger went in. spruce and
# spktoggle.sh own the path on this unit.
if [[ "$(cat /home/ark/.config/.DEVICE)" == "RGB30" ]]; then
   exit 0
fi

if [[ "$(cat /home/ark/.config/.DEVICE)" == "MINILOONG" ]]; then
   if [[ ! -e /sys/class/gpio/gpio16 ]]; then
      echo 16 > /sys/class/gpio/export
      echo out > /sys/class/gpio/gpio16/direction
   fi
   isitminiloong="y"
fi

if [[ "$(dmesg | grep 'headset status is ' | tail -1)" == *"headset status is in"* ]]; then
    amixer -c "$CARD" set 'Playback Path' 'HP'
    if [[ "${isitminiloong}" == "y" ]]; then
       echo 0 > /sys/class/gpio/gpio16/value
    fi
else
    amixer -c "$CARD" set 'Playback Path' 'SPK'
    if [[ "${isitminiloong}" == "y" ]]; then
       echo 1 > /sys/class/gpio/gpio16/value
    fi
fi