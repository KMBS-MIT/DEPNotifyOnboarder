#!/bin/zsh

if [ "$(whoami)" != "root" ] ; then
    echo "This script must run as the root user."
    exit 1
fi

# Removing config files in /var/tmp
rm /var/tmp/depnotify*

# Removing bom files in /var/tmp
rm /var/tmp/com.depnotify.*

# Removing plists in local user folders
rm /Users/*/Library/Preferences/menu.nomad.DEPNotify*

# Restarting cfprefsd due to plist changes
killall cfprefsd

exit 0