#!/bin/bash

PRIVILEGED_HELPER_LABEL=com.robotsandpencils.XcodesApp.Helper

sudo rm /Library/PrivilegedHelperTools/$PRIVILEGED_HELPER_LABEL
sudo rm /Library/LaunchDaemons/$PRIVILEGED_HELPER_LABEL.plist
sudo launchctl bootout system/$PRIVILEGED_HELPER_LABEL      #'Boot-out failed: 36: Operation now in progress' is OK output

echo "Querying launchd..."
LAUNCHD_OUTPUT=$(sudo launchctl list | grep $PRIVILEGED_HELPER_LABEL)


if [ -z "$LAUNCHD_OUTPUT" ]
then
      echo "Finished successfully."
else
      echo "WARNING: $PRIVILEGED_HELPER_LABEL is not removed"
fi
