#!/bin/bash
# probe
if [ ! -f "/etc/sudoers.d/$USER" ]; then
  echo "Adding $USER to sudoers"
  echo "$USER ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USER > /dev/null
  if [[ $? != "0" ]]; then
    echo ""
    echo "Couldn't complete this successfully. :("
    echo ""
  else
    echo ""
    echo "This completed successfully! :)"
    echo ""
  fi
else
  echo ""
  echo "This user should already be able to use sudo without needing a password."
  echo ""
fi
