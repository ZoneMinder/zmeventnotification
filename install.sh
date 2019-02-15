#!/bin/bash

TARGET_BIN='/usr/bin'
TARGET_ZMES_CONFIG='/etc'
TARGET_HOOK_CONFIG='/var/detect/config'
WEB_OWNER='www-data' # change to apache or whomever your distro web user is

# make this empty if you don't want backups
MAKE_CONFIG_BACKUP='-b'

echo '***** Installing ES **********'
install -m 755 -o "${WEB_OWNER}" zmeventnotification.pl "${TARGET_BIN}"

echo '***** Installing Hooks **********'
cd hook
install -m 755 -o "${WEB_OWNER}" detect_wrapper.sh "${TARGET_BIN}"
install -m 755 -o "${WEB_OWNER}" detect_yolo.py "${TARGET_BIN}"
install -m 755 -o "${WEB_OWNER}" detect_hog.py "${TARGET_BIN}"
python setup.py install 
cd ..

echo
read -p "Replace zmes and object config files? [y/N]?:" confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1


echo '***** Replacing config files *****'
install ${MAKE_CONFIG_BACKUP} -o "${WEB_OWNER}" -m 644 hook/objectconfig.ini "${TARGET_HOOK_CONFIG}"
install ${MAKE_CONFIG_BACKUP} -o "${WEB_OWNER}"  -m 644 zmeventnotification.ini "${TARGET_ZMES_CONFIG}"

cd ..
