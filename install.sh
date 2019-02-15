#!/bin/bash

TARGET_BIN='/usr/bin'
TARGET_ZMES_CONFIG='/etc'
TARGET_HOOK_CONFIG='/var/detect/config'

# make this empty if you don't want backups
MAKE_CONFIG_BACKUP='-b'

install -m 755 zmeventnotification.pl "${TARGET_BIN}"
install ${MAKE_CONFIG_BACKUP}  -m 644 zmeventnotification.ini "${TARGET_ZMES_CONFIG}"

cd hook
install -m 755 detect_wrapper.sh "${TARGET_BIN}"
install -m 755 detect_yolo.py "${TARGET_BIN}"
install -m 755 detect_hog.py "${TARGET_BIN}"

install ${MAKE_CONFIG_BACKUP} -m 644 objectconfig.ini "${TARGET_HOOK_CONFIG}"
python setup.py install 
cd ..
