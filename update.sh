#!/bin/bash
RED='\033[0;31m'

echo "Start a update in server!"

# don't start with no sudo privileges
if [ "$USER" = "root" ] ; then
        echo "";
else
        echo "You need a sudo privileges.";
        exit 0;
fi

# update a debian server and check reboot required
updateserver(){
    apt update
    apt upgrade
    apt autoremove
    if [ ! -f /var/run/reboot-required ]; then
        # no reboot required (0=OK)
        echo "OK: no reboot required"
    else
        # reboot required (1=WARN)
        echo "${RED}WARNING: `cat /var/run/reboot-required`"
    fi
}

# update nextcloud to a new version with docker-compose
updatenc(){
    docker-compose build --no-cache
    docker-compose down
    docker-compose up -d
}

# run functions
updateserver
updatenc

# with no erros, finish
echo "Successful update and upgrade!"
exit 0
