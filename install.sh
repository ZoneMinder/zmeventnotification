#!/bin/bash

# --- Change these --
TARGET_BIN='/usr/bin'
TARGET_ZMES_CONFIG='/etc'
TARGET_HOOK_CONFIG_BASE='/var/detect'

WGET=$(which wget)
WEB_OWNER=$(ps -ef | grep -E '(httpd|hiawatha|apache|apache2|nginx)' | grep -v whoami | grep -v root | head -n1 | awk '{print $1}' )
WEB_GROUP=${WEB_OWNER}
# make this empty if you don't want backups
MAKE_CONFIG_BACKUP='-b'
# --- end of change these ---

# set default values 
WEB_OWNER=${WEB_OWNER:-www-data}
WGET=${WGET:-/usr/bin/wget}

print_error() {
    COLOR="\033[1;31m"
    NOCOLOR="\033[0m"
    echo -e "${COLOR}ERROR:${NOCOLOR}$1"
}

print_warning() {
    COLOR="\033[0;33m"
    NOCOLOR="\033[0m"
    echo -e "${COLOR}WARNING:${NOCOLOR}$1"
}

print_success() {
    COLOR="\033[1;32m"
    NOCOLOR="\033[0m"
    echo -e "${COLOR}Success:{NOCOLOR}$1"
}

# generic confirm function that returns 0 for yes and 1 for no
confirm() {
    display_str=$1
    default_ans=$2
    if [[ $default_ans == 'y/N' ]]
    then
       must_match='[yY]'
    else
       must_match='[nN]'
    fi
    read -p "${display_str} [${default_ans}]:" ans
    [[ $ans == $must_match ]]   
}

# Are we running as root? If not, install may fail
check_root() {
    if [[ $EUID -ne 0 ]]
    then
        echo 
        echo "********************************************************************************"
        print_warning "Unless you have changed paths, this script requires to be run as sudo"
        echo "********************************************************************************"
        echo
        [[ ${INTERACTIVE} == 'yes' ]] && read -p "Press any key to continue or Ctrl+C to quit and run again with sudo..."

    fi
}

# Some of these may be default values, so give user a change to change
verify_config() {

    if [[ ${INTERACTIVE} == 'no' && 
          ( ${INSTALL_ES} == 'prompt' || ${INSTALL_HOOK} == 'prompt' ||
            ${INSTALL_HOOK_CONFIG} == 'prompt' || ${INSTALL_ES_CONFIG} == 'prompt' ) 
       ]] 
    then
        print_error 'In non-interactive mode, you need to specify flags for all components'
        echo
        exit
    fi

    echo
    echo ----------- Configured Values ----------------------------
    echo "Your webserver user seems to be ${WEB_OWNER}"
    echo "wget is at ${WGET}"
    echo
    echo "Install Event Server: ${INSTALL_ES}"
    echo "Install Event Server config: ${INSTALL_ES_CONFIG}"
    echo "Install Hooks: ${INSTALL_HOOK}"
    echo "Install Hooks config: ${INSTALL_HOOK_CONFIG}"
    echo
    [[ ${INSTALL_ES} != 'no' ]] && echo "The Event Server will be installed to ${TARGET_BIN}"
    [[ ${INSTALL_ES_CONFIG} != 'no' ]] && echo "The Event Server config will be installed to ${TARGET_ZMES_CONFIG}"

    [[ ${INSTALL_HOOK} != 'no' ]] && echo "The hook files will be installed to ${TARGET_HOOK_CONFIG_BASE} sub-folders"
    [[ ${INSTALL_HOOK_CONFIG} != 'no' ]] && echo "The hook config files will be installed to ${TARGET_HOOK_CONFIG_BASE} sub-folders"
    echo
     [[ ${INTERACTIVE} == 'yes' ]] && read -p "If any of this looks wrong, please hit Ctrl+C and edit the variables in this script..."

}


# move proc for zmeventnotification.pl
install_es() {
    echo '***** Installing ES **********'
    install -m 755 -o "${WEB_OWNER}" -g "${WEB_GROUP}" zmeventnotification.pl "${TARGET_BIN}"
    echo "Done, but you will still have to manually install all ES dependencies as per https://github.com/pliablepixels/zmeventserver#how-do-i-install-it"
}

# install proc for ML hooks
install_hook() {
    echo '***** Installing Hooks **********'
    mkdir -p "${TARGET_HOOK_CONFIG_BASE}/config" 2>/dev/null
    mkdir -p "${TARGET_HOOK_CONFIG_BASE}/images" 2>/dev/null
    mkdir -p "${TARGET_HOOK_CONFIG_BASE}/models/yolov3" 2>/dev/null
    mkdir -p "${TARGET_HOOK_CONFIG_BASE}/models/tinyyolo" 2>/dev/null

    # If you don't already have data files, get them
    # First YOLOV3
    echo 'Checking for YoloV3 data files....'
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
    echo 'Checking for TinyYOLO data files...'
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
    chown -R ${WEB_OWNER}:${WEB_GROUP} "${TARGET_HOOK_CONFIG_BASE}"

    # Now install the ML hooks
    cd hook
    pip install -r  requirements.txt 
    install -m 755 -o "${WEB_OWNER}" detect_wrapper.sh "${TARGET_BIN}"
    install -m 755 -o "${WEB_OWNER}" detect_yolo.py "${TARGET_BIN}"
    install -m 755 -o "${WEB_OWNER}" detect_hog.py "${TARGET_BIN}"
    python setup.py install 
    echo "Done"
    cd ..
}


install_es_config() {
    echo 'Replacing ES config file'
    install ${MAKE_CONFIG_BACKUP} -o "${WEB_OWNER}" -g "${WEB_GROUP}"  -m 644 zmeventnotification.ini "${TARGET_ZMES_CONFIG}"
    echo "Done"
    echo "====> Remember to fill in the right values in the config files, or your system won't work! <============="
    echo
}

install_hook_config() {
    echo 'Replacing Hook config file'
    install ${MAKE_CONFIG_BACKUP} -o "${WEB_OWNER}" -g "${WEB_GROUP}" -m 644 hook/objectconfig.ini "${TARGET_HOOK_CONFIG_BASE}/config"
    echo "Done"
    echo "====> Remember to fill in the right values in the config files, or your system won't work! <============="
    echo "====> If you changed $TARGET_HOOK_CONFIG_BASE remember to fix  ${TARGET_BIN}/detect_wrapper.sh! <========"
    echo
}

display_help() {
    cat << EOF
    
    $0 [-h|--help] [--install_es|--no_install_es] [--install_hook|--no_install_hook] [--install_config|--no_install_config]

        When used without any parameters executes in interactive mode

        -h: This help

        --install-es: installs Event Server without prompting
        --no-install-es: skips Event Server install without prompting

        --install-hook: installs hooks without prompting
        --no_install_hook: skips hooks install without prompting

        --install-config: installs/overwrites config files without prompting
        --no-install-config: skips config install without prompting

        --no-interactive: run automatically, but you need to specify flags for all components


EOF
}

check_args() {
    # credit: https://stackoverflow.com/a/14203146/1361529
    INSTALL_ES='prompt'
    INSTALL_HOOK='prompt'
    INSTALL_ES_CONFIG='prompt'
    INSTALL_HOOK_CONFIG='prompt'
    INTERACTIVE='yes'

    for key in "${cmd_args[@]}"
    do
    case $key in
        -h|--help)
            display_help && exit
            shift
            ;;
        --no-interactive)
            INTERACTIVE='no'
            shift
            ;;
        --install-es)
            INSTALL_ES='yes'
            shift 
            ;;
        --no-install-es)
            INSTALL_ES='no'
            shift
            ;;
        --install-hook)
            INSTALL_HOOK='yes'
            shift 
            ;;
        --no-install-hook)
            INSTALL_HOOK='no'
            shift
            ;;
        --install-config)
            INSTALL_HOOK_CONFIG='yes'
            INSTALL_ES_CONFIG='yes'
            shift
            ;;
        --no-install-config)
            INSTALL_ES_CONFIG='no'
            INSTALL_HOOK_CONFIG='no'
            shift
            ;;
        *)  # unknown option
            shift 
            ;;
    esac
    done  

    [[ ${INSTALL_ES} == 'no' ]] && INSTALL_ES_CONFIG='no'
    [[ ${INSTALL_ES} == 'prompt' && ${INSTALL_ES_CONFIG} == 'yes' ]] && INSTALL_ES_CONFIG='prompt'

    [[ ${INSTALL_HOOK} == 'no' ]] && INSTALL_HOOK_CONFIG='no'
    [[ ${INSTALL_HOOK} == 'prompt' && ${INSTALL_HOOK_CONFIG} == 'yes' ]] && INSTALL_HOOK_CONFIG='prompt'

}


###################################################
# script main
###################################################
cmd_args=("$@") # because we need a function to access them
check_args
check_root
verify_config

[[ ${INSTALL_ES} == 'yes' || $(confirm 'Install Event Server' 'y/N') ]]  && install_es || echo 'Skipping Event Server'
[[ ${INSTALL_ES_CONFIG} == 'yes' || $(confirm 'Install Event Server Config' 'y/N') ]] && install_es_config || echo 'Skipping Event Server config'


[[ ${INSTALL_HOOK} == 'yes' || $(confirm 'Install Hooks' 'y/N') ]]  && install_hook || echo 'Skipping Hook'
[[ ${INSTALL_HOOK_CONFIG} == 'yes' || $(confirm 'Install Hook Config' 'y/N') ]] && install_hook_config || echo 'Skipping Hook config'
