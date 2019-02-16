#!/bin/bash

# --- Change these --
TARGET_BIN='/usr/bin'
TARGET_ZMES_CONFIG='/etc'
TARGET_HOOK_CONFIG_BASE='/var/detect'

WGET=$(which wget)
WEB_OWNER=$(ps -ef | grep -E '(httpd|hiawatha|apache|apache2|nginx)' | grep -v whoami | grep -v root | head -n1 | awk '{print $1}' )
# make this empty if you don't want backups
MAKE_CONFIG_BACKUP='-b'
# --- end of change these ---

# set deafault values 
WEB_OWNER=${WEB_OWNER:-www-data}
WGET=${WGET:-/usr/bin/wget}


# Are we running as root? If not, install may fail
if [[ $EUID -ne 0 ]]
then
    echo 
    echo "--------------------------------------------------------------------------------"
    echo "WARNING: Unless you have changed paths, this script requires to be run as sudo"
    echo "--------------------------------------------------------------------------------"
    echo
    read -p "Press any key to continue or Ctrl+C to quit and run again with sudo..."

fi

# Some of these may be default values, so give user a change to change
echo
echo ----------- Configured Values ----------------------------
echo "Your webserver user seems to be ${WEB_OWNER}"
echo "wget is at ${WGET}"
echo "The Event Server will be installed to ${TARGET_BIN}"
echo "The Event Server config will be installed to ${TARGET_ZMES_CONFIG}"
echo "If enabled, the hook data/config files will be installed to ${TARGET_HOOK_CONFIG_BASE} sub-folders"
echo
read -p "If any of this looks wrong, please hit Ctrl+C and edit the variables in this script..."


# install proc for zmeventnotification.pl
echo '***** Installing ES **********'
install -m 755 -o "${WEB_OWNER}" zmeventnotification.pl "${TARGET_BIN}"
echo "Done"

read -p "Install machine learning hooks? [y/N]" confirm

if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]
then
    # install proc for ML hooks
    echo '***** Installing Hooks **********'
    mkdir -p "${TARGET_HOOK_CONFIG_BASE}/config" 2>/dev/null
    mkdir -p "${TARGET_HOOK_CONFIG_BASE}/images" 2>/dev/null
    mkdir -p "${TARGET_HOOK_CONFIG_BASE}/models/yolov3" 2>/dev/null
    mkdir -p "${TARGET_HOOK_CONFIG_BASE}/models/tinyyolo" 2>/dev/null

    # If you don't already have data files, get them
    # First YOLOV3
    echo "Checking for YoloV3 data files...."
    targets=('yolov3.cfg' 'yolov3_classes.txt' 'yolov3.weights')
    sources=('https://raw.githubusercontent.com/pjreddie/darknet/master/cfg/yolov3.cfg'
             'https://raw.githubusercontent.com/pjreddie/darknet/master/data/coco.names'
             'https://pjreddie.com/media/files/yolov3.weights -O /var/detect/models/yolov3/yolov3.weights')

    for ((i=0;i<${#targets[@]};++i))
    do
        if [ ! -f "${TARGET_HOOK_CONFIG_BASE}/models/yolov3/${targets[i]}" ]
        then
            ${WGET} "${sources[i]}"  -O"${TARGET_HOOK_CONFIG_BASE}/models/yolov3/${targets[i]}"
        else
            echo "${targets[i]} exists, no need to download"

        fi
    done


    # Next up, TinyYOLO
    echo
    echo "Checking for TinyYOLO data files..."
    targets=('yolov3-tiny.cfg' 'yolov3-tiny.txt' 'yolov3-tiny.weights')
    sources=('https://raw.githubusercontent.com/pjreddie/darknet/master/cfg/yolov3-tiny.cfg'
             'https://raw.githubusercontent.com/pjreddie/darknet/master/data/coco.names'
             'https://pjreddie.com/media/files/yolov3-tiny.weights')

    for ((i=0;i<${#targets[@]};++i))
    do
        if [ ! -f "${TARGET_HOOK_CONFIG_BASE}/models/tinyyolo/${targets[i]}" ]
        then
            ${WGET} "${sources[i]}"  -O"${TARGET_HOOK_CONFIG_BASE}/models/tinyyolo/${targets[i]}"
        else
            echo "${targets[i]} exists, no need to download"

        fi
    done


    # Make sure webserver can access them
    chown -R ${WEB_OWNER} "${TARGET_HOOK_CONFIG_BASE}"

    # Now install the ML hooks
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
# You may not want this every time
read -p "Replace zmes and object config files? [y/N]?:" confirm 


if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]
then
    echo '***** Replacing config files *****'
    install ${MAKE_CONFIG_BACKUP} -o "${WEB_OWNER}" -m 644 hook/objectconfig.ini "${TARGET_HOOK_CONFIG_BASE}/config"
    install ${MAKE_CONFIG_BACKUP} -o "${WEB_OWNER}"  -m 644 zmeventnotification.ini "${TARGET_ZMES_CONFIG}"
    echo "Done"
    echo "====> Remember to fill in the right values in the config files, or your system won't work! <============="
    echo "====> If you changed $TARGET_HOOK_CONFIG_BASE remember to fix  ${TARGET_BIN}/detect_wrapper.sh! <========"
    echo
fi

