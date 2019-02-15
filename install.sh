#!/bin/bash

TARGET_BIN='/usr/bin'
TARGET_ZMES_CONFIG='/etc'
TARGET_HOOK_CONFIG='/var/detect/config'
WEB_OWNER=$(ps -ef | grep -E '(httpd|hiawatha|apache|apache2)' | grep -v whoami | grep -v root | head -n1 | awk '{print $1}' )
#WEB_OWNER='www-data' # change to apache or whomever your distro web user is

# make this empty if you don't want backups
MAKE_CONFIG_BACKUP='-b'


if [[ $EUID -ne 0 ]]
then
    echo 
    echo "---------------------------- ---------------------------------------------------"
    echo "WARNING: Unless you have changed paths, this script requires to be run as sudo"
    echo "--------------------------------------------------------------------------------"
    echo
    read -p "Press any key to continue or ^C to quit and run again with sudo..."

fi

echo "Detected web group as ${WEB_OWNER}"
echo



echo '***** Installing ES **********'
install -m 755 -o "${WEB_OWNER}" zmeventnotification.pl "${TARGET_BIN}"
echo "Done"

read -p "Install machine learning hooks? [Y/n]" confirm

if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]
then
    echo '***** Installing Hooks **********'
    cd hook
    pip install -r  requirements.txt 
    install -m 755 -o "${WEB_OWNER}" detect_wrapper.sh "${TARGET_BIN}"
    install -m 755 -o "${WEB_OWNER}" detect_yolo.py "${TARGET_BIN}"
    install -m 755 -o "${WEB_OWNER}" detect_hog.py "${TARGET_BIN}"
    python setup.py install 
    echo "Done"
    cd ..
fi

echo
read -p "Replace zmes and object config files? [y/N]?:" confirm 


if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]
then
    echo '***** Replacing config files *****'
    install ${MAKE_CONFIG_BACKUP} -o "${WEB_OWNER}" -m 644 hook/objectconfig.ini "${TARGET_HOOK_CONFIG}"
    install ${MAKE_CONFIG_BACKUP} -o "${WEB_OWNER}"  -m 644 zmeventnotification.ini "${TARGET_ZMES_CONFIG}"
    echo "Done"
fi

