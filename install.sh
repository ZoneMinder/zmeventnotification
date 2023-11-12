#!/bin/bash

#-----------------------------------------------------
# Install script for the EventServer and the 
# machine learning hooks
#
# /install.sh --help
#
# Note that this does not install all the event server
# dependencies. You still need to follow the README
#
# It does however try to install all the hook dependencies
#
#-----------------------------------------------------

# --- Change these if you want --

PYTHON=${PYTHON:-python3}
PIP=${PIP:-pip3}
INSTALLER=${INSTALLER:-$(which apt-get || which yum)}

# Models to install
# If you do not want them, pass them as variables to install.sh
# example: sudo INSTALL_YOLO4=no ./install.sh

INSTALL_YOLOV3=${INSTALL_YOLOV3:-yes}
INSTALL_TINYYOLOV3=${INSTALL_TINYYOLOV3:-yes}
INSTALL_YOLOV4=${INSTALL_YOLOV4:-yes}
INSTALL_TINYYOLOV4=${INSTALL_TINYYOLOV4:-yes}
INSTALL_CORAL_EDGETPU=${INSTALL_CORAL_EDGETPU:-no}


TARGET_CONFIG=${TARGET_CONFIG:-'/etc/zm'}
TARGET_DATA=${TARGET_DATA:-'/var/lib/zmeventnotification'}
TARGET_BIN_ES=${TARGET_BIN_ES:-'/usr/bin'}
TARGET_BIN_HOOK=${TARGET_BIN_HOOK:-'/var/lib/zmeventnotification/bin'}

WGET=${WGET:-$(which wget)}
_WEB_OWNER_FROM_PS=$(ps xao user,group,comm | grep -E '(httpd|hiawatha|apache|apache2|nginx)' | grep -v whoami | grep -v root | head -n1 | awk '{print $1}')
#_WEB_OWNER='www-data' # uncomment this if the above mechanism fails

_WEB_GROUP_FROM_PS=$(ps xao user,group,comm | grep -E '(httpd|hiawatha|apache|apache2|nginx)' | grep -v whoami | grep -v root | head -n1 | awk '{print $2}')
#_WEB_GROUP='www-data' # uncomment if above line fails
# make this empty if you do not want backups
MAKE_CONFIG_BACKUP='--backup=numbered'

# --- end of change these ---

# set default values 
# if we have a value from ps use it, otherwise look in env

WEB_OWNER=${WEB_OWNER:-${_WEB_OWNER_FROM_PS}}
WEB_GROUP=${WEB_GROUP:-${_WEB_GROUP_FROM_PS}}

# if we do not have a value from ps or env, use default

WEB_OWNER=${WEB_OWNER:-'www-data'}
WEB_GROUP=${WEB_GROUP:-'www-data'}


# utility functions for color coded pretty printing
print_error() {
    COLOR="\033[1;31m"
    NOCOLOR="\033[0m"
    echo -e "${COLOR}ERROR:${NOCOLOR}$1"
}

print_important() {
    COLOR="\033[0;34m"
    NOCOLOR="\033[0m"
    echo -e "${COLOR}IMPORTANT:${NOCOLOR}$1"
}

print_warning() {
    COLOR="\033[0;33m"
    NOCOLOR="\033[0m"
    echo -e "${COLOR}WARNING:${NOCOLOR}$1"
}

print_success() {
    COLOR="\033[1;32m"
    NOCOLOR="\033[0m"
    echo -e "${COLOR}Success:${NOCOLOR}$1"
}

get_distro() {
    local DISTRO=`(lsb_release -ds || cat /etc/*release || uname -om ) 2>/dev/null | head -n1`
    local DISTRO_NORM='ubuntu'
    if echo "${DISTRO}" | grep -iqF 'ubuntu'; then
        DISTRO_NORM='ubuntu'
    elif echo "${DISTRO}" | grep -iqF 'centos'; then
        DISTRO_NORM='centos'
    fi
    echo ${DISTRO_NORM}
}

get_installer() {
    local DISTRO=$(get_distro)
    local installer='apt-get'
    case $DISTRO in
        ubuntu)
            installer='apt-get'
            ;;
        centos)
            installer='yum'
            ;;
    esac
    echo ${installer}        
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
    echo "Your distro seems to be ${DISTRO}"
    echo "Your webserver user seems to be ${WEB_OWNER}"
    echo "Your webserver group seems to be ${WEB_GROUP}"
    echo "wget is ${WGET}"
    echo "installer software is ${INSTALLER}"

    echo "Install Event Server: ${INSTALL_ES}"
    echo "Install Event Server config: ${INSTALL_ES_CONFIG}"
    echo "Install Hooks: ${INSTALL_HOOK}"
    echo "Install Hooks config: ${INSTALL_HOOK_CONFIG}"
    echo "Upgrade Hooks config (if applicable): ${HOOK_CONFIG_UPGRADE}"
    echo "Download and install models (if needed): ${DOWNLOAD_MODELS}"
    echo

    [[ ${INSTALL_ES} != 'no' ]] && echo "The Event Server will be installed to ${TARGET_BIN_ES}"
    [[ ${INSTALL_ES_CONFIG} != 'no' ]] && echo "The Event Server config will be installed to ${TARGET_CONFIG}"

    [[ ${INSTALL_HOOK} != 'no' ]] && echo "Hooks will be installed to ${TARGET_DATA} sub-folders"
    [[ ${INSTALL_HOOK_CONFIG} != 'no' ]] && echo "Hook config files will be installed to ${TARGET_CONFIG}"

    echo
    if [[ ${DOWNLOAD_MODELS} == 'yes' ]]
    then
        echo "Models that will be checked/installed:"
        echo "(Note, if you have already downloaded a model, it will not be deleted)"
        echo "Yolo V3 (INSTALL_YOLOV3): ${INSTALL_YOLOV3}"
        echo "TinyYolo V3 (INSTALL_TINYYOLOV3): ${INSTALL_TINYYOLOV3}"
        echo "Yolo V4 (INSTALL_YOLOV4): ${INSTALL_YOLOV4}"
        echo "Tiny Yolo V4 (INSTALL_TINYYOLOV4)": ${INSTALL_TINYYOLOV4}
        echo "Google Coral Edge TPU (INSTALL_CORAL_EDGETPU)": ${INSTALL_CORAL_EDGETPU}

    fi
    echo
    if [[ ${INTERACTIVE} == 'no' ]]
    then
        echo "Non interactive mode, installer will answer yes to all questions."
        if [[ ${INSTALLER} == 'apt-get' ]]
        then
            INSTALLER="${INSTALLER} -yq"
        else
            INSTALLER="${INSTALLER} -y"
        fi
    fi
     [[ ${INTERACTIVE} == 'yes' ]] && read -p "If any of this looks wrong, please hit Ctrl+C and edit the variables in this script..."

}


# move proc for zmeventnotification.pl
install_es() {
    echo '*** Installing ES Dependencies ***'
    if [[ "$DISTRO" == "ubuntu" || "$DISTRO" == "debian" ]]; then
      echo "$INSTALLER install libconfig-inifiles-perl libcrypt-mysql-perl libcrypt-eksblowfish-perl libmodule-build-perl libyaml-perl libjson-per liblwp-protocol-https-perl libgeos-devl"
      $INSTALLER install libconfig-inifiles-perl libcrypt-mysql-perl libcrypt-eksblowfish-perl libmodule-build-perl libyaml-perl
      echo "$INSTALLER install libnet-websocket-server-perl"
      $INSTALLER install libnet-websocket-server-perl
    else
      echo "Not ubuntu or debian"
    fi

    echo '*** Installing ES ***'
    mkdir -p "${TARGET_DATA}/push" 2>/dev/null
    install -m 755 -o "${WEB_OWNER}" -g "${WEB_GROUP}" zmeventnotification.pl "${TARGET_BIN_ES}" && 
            print_success "Completed, but you will still have to install ES dependencies as per https://zmeventnotification.readthedocs.io/en/latest/guides/install.html#install-dependencies"  || print_error "failed"
    #echo "Done, but you will still have to manually install all ES dependencies as per https://github.com/pliablepixels/zmeventnotification#how-do-i-install-it"
}

# install proc for ML hooks
install_hook() {

    echo "Installing pip..."
    ${PY_SUDO} ${INSTALLER} install pip
    echo "Installing python3-opencv..."
    ${PY_SUDO} ${INSTALLER} install python3-opencv

    echo '*** Installing Hooks ***'
    mkdir -p "${TARGET_DATA}/bin" 2>/dev/null
    rm -fr  "${TARGET_DATA}/bin/*" 2>/dev/null

    #don't delete contrib so custom user files remain
    mkdir -p "${TARGET_DATA}/contrib" 2>/dev/null

    mkdir -p "${TARGET_DATA}/images" 2>/dev/null
    mkdir -p "${TARGET_DATA}/mlapi" 2>/dev/null
    mkdir -p "${TARGET_DATA}/known_faces" 2>/dev/null
    mkdir -p "${TARGET_DATA}/unknown_faces" 2>/dev/null
    mkdir -p "${TARGET_DATA}/models/yolov3" 2>/dev/null
    mkdir -p "${TARGET_DATA}/models/tinyyolov3" 2>/dev/null
    mkdir -p "${TARGET_DATA}/models/tinyyolov4" 2>/dev/null
    mkdir -p "${TARGET_DATA}/models/yolov4" 2>/dev/null
    mkdir -p "${TARGET_DATA}/models/coral_edgetpu" 2>/dev/null
    mkdir -p "${TARGET_DATA}/misc" 2>/dev/null
    echo "everything that does not fit anywhere else :-)" > "${TARGET_DATA}/misc/README.txt" 2>/dev/null
    
    if [ "${DOWNLOAD_MODELS}" == "yes" ]
    then

        if [ "${INSTALL_CORAL_EDGETPU}" == "yes" ]
        then
            # Coral files
            #echo
            #echo "Installing pycoral libs, if needed..."
            #${PY_SUDO} apt-get install libedgetpu1-std -qq
            #${PY_SUDO} ${INSTALLER} install python3-pycoral -qq
            

            echo 'Checking for Google Coral Edge TPU data files...'
            targets=( 'coco_indexed.names' 'ssd_mobilenet_v2_coco_quant_postprocess_edgetpu.tflite' 'ssdlite_mobiledet_coco_qat_postprocess_edgetpu.tflite' 'ssd_mobilenet_v2_face_quant_postprocess_edgetpu.tflite')
            sources=('https://dl.google.com/coral/canned_models/coco_labels.txt'
                     'https://github.com/google-coral/edgetpu/raw/master/test_data/ssd_mobilenet_v2_coco_quant_postprocess_edgetpu.tflite'
                     'https://github.com/google-coral/test_data/raw/master/ssdlite_mobiledet_coco_qat_postprocess_edgetpu.tflite'
                     'https://github.com/google-coral/test_data/raw/master/ssd_mobilenet_v2_face_quant_postprocess_edgetpu.tflite'

                    )

            for ((i=0;i<${#targets[@]};++i))
            do
                if [ ! -f "${TARGET_DATA}/models/coral_edgetpu/${targets[i]}" ]
                then
                    ${WGET} "${sources[i]}"  -O"${TARGET_DATA}/models/coral_edgetpu/${targets[i]}"
                else
                    echo "${targets[i]} exists, no need to download"

                fi
            done
        fi

        if [ "${INSTALL_YOLOV3}" == "yes" ]
        then
        # If you don't already have data files, get them
        # First YOLOV3
        echo 'Checking for YoloV3 data files....'
        targets=('yolov3.cfg' 'coco.names' 'yolov3.weights')
        sources=('https://raw.githubusercontent.com/pjreddie/darknet/master/cfg/yolov3.cfg'
                'https://raw.githubusercontent.com/pjreddie/darknet/master/data/coco.names'
                'https://pjreddie.com/media/files/yolov3.weights')

        [ -f "${TARGET_DATA}/models/yolov3/yolov3_classes.txt" ] && rm "${TARGET_DATA}/models/yolov3/yolov3_classes.txt"
        

        for ((i=0;i<${#targets[@]};++i))
        do
            if [ ! -f "${TARGET_DATA}/models/yolov3/${targets[i]}" ]
            then
                ${WGET} "${sources[i]}"  -O"${TARGET_DATA}/models/yolov3/${targets[i]}"
            else
                echo "${targets[i]} exists, no need to download"

            fi
        done
        fi

        if [ "${INSTALL_TINYYOLOV3}" == "yes" ]
        then
        # Next up, TinyYOLOV3

        [ -d "${TARGET_DATA}/models/tinyyolo" ] && mv "${TARGET_DATA}/models/tinyyolo" "${TARGET_DATA}/models/tinyyolov3"
        echo
        echo 'Checking for TinyYOLOV3 data files...'
        targets=('yolov3-tiny.cfg' 'coco.names' 'yolov3-tiny.weights')
        sources=('https://raw.githubusercontent.com/pjreddie/darknet/master/cfg/yolov3-tiny.cfg'
                'https://raw.githubusercontent.com/pjreddie/darknet/master/data/coco.names'
                'https://pjreddie.com/media/files/yolov3-tiny.weights')

        [ -f "${TARGET_DATA}/models/tinyyolov3/yolov3-tiny.txt" ] && rm "${TARGET_DATA}/models/yolov3/yolov3-tiny.txt"

        for ((i=0;i<${#targets[@]};++i))
        do
            if [ ! -f "${TARGET_DATA}/models/tinyyolov3/${targets[i]}" ]
            then
                ${WGET} "${sources[i]}"  -O"${TARGET_DATA}/models/tinyyolov3/${targets[i]}"
            else
                echo "${targets[i]} exists, no need to download"

            fi
        done
        fi

        if [ "${INSTALL_TINYYOLOV4}" == "yes" ]
        then
            # Next up, TinyYOLOV4
            echo
            echo 'Checking for TinyYOLOV4 data files...'
            targets=('yolov4-tiny.cfg' 'coco.names' 'yolov4-tiny.weights')
            sources=('https://raw.githubusercontent.com/AlexeyAB/darknet/master/cfg/yolov4-tiny.cfg'
                    'https://raw.githubusercontent.com/pjreddie/darknet/master/data/coco.names'
                    'https://github.com/AlexeyAB/darknet/releases/download/darknet_yolo_v4_pre/yolov4-tiny.weights')

            for ((i=0;i<${#targets[@]};++i))
            do
                if [ ! -f "${TARGET_DATA}/models/tinyyolov4/${targets[i]}" ]
                then
                    ${WGET} "${sources[i]}"  -O"${TARGET_DATA}/models/tinyyolov4/${targets[i]}"
                else
                    echo "${targets[i]} exists, no need to download"

                fi
            done
        fi

        if [ "${INSTALL_YOLOV4}" == "yes" ]
        then

            # Next up, YoloV4
            if [ -d "${TARGET_DATA}/models/cspn" ]
            then 
                echo "Removing old CSPN files, it is YoloV4 now"
                rm -rf "${TARGET_DATA}/models/cspn" 2>/dev/null
            fi

            
            echo
            echo 'Checking for YOLOV4 data files...'
            print_warning 'Note, you need OpenCV 4.4+ for Yolov4 to work'
            targets=('yolov4.cfg' 'coco.names' 'yolov4.weights')
            sources=('https://raw.githubusercontent.com/AlexeyAB/darknet/master/cfg/yolov4.cfg'
                    'https://raw.githubusercontent.com/pjreddie/darknet/master/data/coco.names'
                    'https://github.com/AlexeyAB/darknet/releases/download/darknet_yolo_v3_optimal/yolov4.weights'
                    )

            for ((i=0;i<${#targets[@]};++i))
            do
                if [ ! -f "${TARGET_DATA}/models/yolov4/${targets[i]}" ]
                then
                    ${WGET} "${sources[i]}"  -O"${TARGET_DATA}/models/yolov4/${targets[i]}"
                else
                    echo "${targets[i]} exists, no need to download"

                fi
            done
        fi
    else
        echo "Skipping model downloads"
    fi
    
    # Now install the ML hooks

    echo "*** Installing push api plugins ***"
     install -m 755 -o "${WEB_OWNER}" pushapi_plugins/pushapi_pushover.py "${TARGET_BIN_HOOK}"

    echo "*** Installing detection scripts ***"
    install -m 755 -o "${WEB_OWNER}" hook/zm_event_start.sh "${TARGET_BIN_HOOK}"
    install -m 755 -o "${WEB_OWNER}" hook/zm_event_end.sh "${TARGET_BIN_HOOK}"
    install -m 755 -o "${WEB_OWNER}" hook/zm_detect.py "${TARGET_BIN_HOOK}"
    install -m 755 -o "${WEB_OWNER}" hook/zm_train_faces.py "${TARGET_BIN_HOOK}"
    #python setup.py install && print_success "Done" || print_error "python setup failed"

    echo
    echo "*** Installing user contributions ***"
    cp docs/guides/contrib_guidelines.rst "${TARGET_DATA}/contrib"
    for file in contrib/*; do
    echo "Copying over ${file}..."
      install -m 755 -o "${WEB_OWNER}" "$file" "${TARGET_DATA}/contrib"
    done
    echo
    

    echo "Removing old version of zmes_hook_helpers, if any"
    ${PY_SUDO} ${PIP} uninstall -y zmes-hooks   >/dev/null 2>&1
    ${PY_SUDO} ${PIP} uninstall -y zmes_hook_helpers   >/dev/null 2>&1
 

    ZM_DETECT_VERSION=`./hook/zm_detect.py --bareversion`
    if [ "$ZM_DETECT_VERSION" == "" ]; then
      echo "Failed to detect hooks version."
    else
      echo "__version__ = \"${ZM_DETECT_VERSION}\"" > hook/zmes_hook_helpers/__init__.py
      echo "VERSION=__version__" >> hook/zmes_hook_helpers/__init__.py
    fi

    ${PY_SUDO} ${PIP} -v install hook/ && print_opencv_message || print_error "python hooks setup failed"

    echo "Installing package deps..."
    echo "Installing gifsicle, if needed..."
    ${PY_SUDO} ${INSTALLER} install gifsicle -qq

}


# move ES config files
install_es_config() {
    echo 'Replacing ES config & rules file'
    install ${MAKE_CONFIG_BACKUP} -o "${WEB_OWNER}" -g "${WEB_GROUP}"  -m 644 zmeventnotification.ini "${TARGET_CONFIG}" && 
        print_success "config copied" || print_error "could not copy config"
    if [ ! -f "${TARGET_CONFIG}/secrets.ini" ]; then
     install ${MAKE_CONFIG_BACKUP} -o "${WEB_OWNER}" -g "${WEB_GROUP}"  -m 644 secrets.ini "${TARGET_CONFIG}" && 
        print_success "secrets copied" || print_error "could not copy secrets"
    fi
    echo 'Replacing ES rules file'
    install ${MAKE_CONFIG_BACKUP} -o "${WEB_OWNER}" -g "${WEB_GROUP}"  -m 644 es_rules.json "${TARGET_CONFIG}" && 
        print_success "rules copied" || print_error "could not copy rules"


    echo "====> Remember to fill in the right values in the config files, or your system won't work! <============="
    echo
}

# move Hook config files
install_hook_config() {
    echo 'Replacing Hook config file'
    install ${MAKE_CONFIG_BACKUP} -o "${WEB_OWNER}" -g "${WEB_GROUP}" -m 644 hook/objectconfig.ini "${TARGET_CONFIG}" &&
        print_success "config copied" || print_error "could not copy config"
    echo "====> Remember to fill in the right values in the config files, or your system won't work! <============="
    echo "====> If you changed $TARGET_CONFIG remember to fix  ${TARGET_BIN_HOOK}/zm_event_start.sh! <========"
    echo
}

# returns 'ok' if openCV version >= version passed 
check_opencv_version() {
    MAJOR=$1
    MINOR=$2
    CVVERS=`${PYTHON} -c "import cv2; print (cv2.__version__)" 2>/dev/null`
    if [ -z "${CVVERS}" ]; then
            echo "fail"
            return 1
    fi
    IFS='.'
    list=($CVVERS)
    if [ ${list[0]} -ge ${MAJOR} ] && [ ${list[1]} -ge ${MINOR} ]; then
            echo "ok"
            return 0
    else
            echo "fail"
            return 1
    fi
}

print_opencv_message() {

    print_success "Done"

    cat << EOF

    |-------------------------- NOTE -------------------------------------|
    
     Hooks are installed, but please make sure you have the right version
     of OpenCV installed. I recommend removing any pip packages you may
     have installed of opencv* and compiling OpenCV 4.4.x+ from source. 
     See https://zmeventnotification.readthedocs.io/en/latest/guides/hooks.html#opencv-install

    |----------------------------------------------------------------------|

EOF
}

# wuh
display_help() {
    cat << EOF
    
    sudo -H [VAR1=value|VAR2=value...] $0 [-h|--help] [--install-es|--no-install-es] [--install-hook|--no-install-hook] [--install-config|--no-install-config] [--hook-config-upgrade|--no-hook-config-upgrade] [--no-pysudo] [--no-download-models]

        When used without any parameters executes in interactive mode

        -h: This help

        --install-es: installs Event Server without prompting
        --no-install-es: skips Event Server install without prompting

        --install-hook: installs hooks without prompting
        --no-install-hook: skips hooks install without prompting

        --install-config: installs/overwrites config files without prompting
        --no-install-config: skips config install without prompting

        --no-interactive: run automatically, but you need to specify flags for all components

        --no-pysudo: If specified will install python packages 
        without sudo (some users don't install packages globally)

        --no-download-models: If specified will not download any models.
        You may want to do this if using mlapi

        --hook-config-upgrade: Updates objectconfig.ini with any new/modified attributes 
        and creates a sample output file. You will need to manually merge/update/review your real config
        --no-hook-config-upgrade: skips aboe process

        In addition to the above, you can also override all variables used for your own needs 
        Overridable variables are: 

        PYTHON: python interpreter (default: python3)
        PIP: pip package installer (default: pip3)
        WGET: path to wget (default `which wget`)

        INSTALLER: Your OS equivalent of apt-get or yum (default: apt-get or yum)
        INSTALL_YOLOV3: Download and install yolov3 model (default:yes)
        INSTALL_TINYYOLOV3: Download and install tiny yolov3 model (default:yes)
        INSTALL_YOLOV4: Download and install yolov4 model (default:yes)
        INSTALL_TINY_YOLOV4: Download and install tiny yolov4 model (default:yes)
        INSTALL_CORAL_EDGETPU: Download and install coral models (default:no)

        TARGET_CONFIG: Path to ES config dir (default: /etc/zm)
        TARGET_DATA: Path to ES data dir (default: /var/lib/zmeventnotification)
        TARGET_BIN_ES: Path to ES binary (default:/usr/bin)
        TARGET_BIN_HOOK: Path to hook script files (default: /var/lib/zmeventnotification/bin)

        WEB_OWNER: Your webserver user (default: www-data)
        WEB_GROUP: Your webserver group (default: www-data)


EOF
}

# parses arguments and does a bit of conflict sanitization
check_args() {
    # credit: https://stackoverflow.com/a/14203146/1361529
    INSTALL_ES='prompt'
    INSTALL_HOOK='prompt'
    INSTALL_ES_CONFIG='prompt'
    INSTALL_HOOK_CONFIG='prompt'
    INTERACTIVE='yes'
    PY_SUDO='sudo -H'
    DOWNLOAD_MODELS='yes'
    HOOK_CONFIG_UPGRADE='yes'

    for key in "${cmd_args[@]}"
    do
    case $key in
        -h|--help)
            display_help && exit
            shift
            ;;

        --no-download-models)
            DOWNLOAD_MODELS='no'
            shift
            ;;
        --no-pysudo)
            PY_SUDO=''
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
        --no-hook-config-upgrade)
            HOOK_CONFIG_UPGRADE='no'
            shift
            ;;
        --hook-config-upgrade)
            HOOK_CONFIG_UPGRADE='yes'
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

    # if ES won't be installed, doesn't make sense to copy ES config. Umm actually...
    [[ ${INSTALL_ES} == 'no' ]] && INSTALL_ES_CONFIG='no'

    # If we are prompting for ES, lets also prompt for config and not auto
    [[ ${INSTALL_ES} == 'prompt' && ${INSTALL_ES_CONFIG} == 'yes' ]] && INSTALL_ES_CONFIG='prompt'

    # same logic as above
    [[ ${INSTALL_HOOK} == 'no' ]] && INSTALL_HOOK_CONFIG='no'
    [[ ${INSTALL_HOOK} == 'prompt' && ${INSTALL_HOOK_CONFIG} == 'yes' ]] && INSTALL_HOOK_CONFIG='prompt'
}

###################################################
# script main
###################################################
cmd_args=("$@") # because we need a function to access them
check_args
DISTRO=$(get_distro)
check_root
verify_config
echo
echo

[[ ${INSTALL_ES} == 'yes' ]] && install_es
[[ ${INSTALL_ES} == 'no' ]] && echo 'Skipping Event Server install'
if [[ ${INSTALL_ES} == 'prompt' ]] 
then
    confirm 'Install Event Server' 'y/N' && install_es || echo 'Skipping Event Server install'
fi

echo
echo

[[ ${INSTALL_ES_CONFIG} == 'yes' ]] && install_es_config
[[ ${INSTALL_ES_CONFIG} == 'no' ]] && echo 'Skipping Event Server config install'
if [[ ${INSTALL_ES_CONFIG} == 'prompt' ]] 
then
    confirm 'Install Event Server Config' 'y/N' && install_es_config || echo 'Skipping Event Server config install'
fi

echo
echo

[[ ${INSTALL_HOOK} == 'yes' ]] && install_hook 
[[ ${INSTALL_HOOK} == 'no' ]] && echo 'Skipping Hook'
if [[ ${INSTALL_HOOK} == 'prompt' ]] 
then
    confirm 'Install Hook' 'y/N' && install_hook || echo 'Skipping Hook install'
fi

echo
echo

[[ ${INSTALL_HOOK_CONFIG} == 'yes' ]] && install_hook_config
[[ ${INSTALL_HOOK_CONFIG} == 'no' ]] && echo 'Skipping Hook config install'
if [[ ${INSTALL_HOOK_CONFIG} == 'prompt' ]] 
then
    confirm 'Install Hook Config' 'y/N' && install_hook_config || echo 'Skipping Hook config install'
fi

# Make sure webserver can access them
chown -R ${WEB_OWNER}:${WEB_GROUP} "${TARGET_DATA}"


if [ "${INSTALL_CORAL_EDGETPU}" == "yes" ]
then
    cat << EOF
    -------------------------- EdgeTPU note ---------------------------- 

    Note that while edgetpu support has been added, the expectation is 
    that you have followed all the instructions at:
    https://coral.ai/docs/accelerator/get-started/ first. Specifically,
    you need to make sure you have:
    1. Installed the right libedgetpu library (max or std)
    2. Installed the right tensorflow-lite library 
    3. Installed pycoral APIs as per https://coral.ai/software/#pycoral-api

    If you don't, things will break. Further, you also need to make sure 
    your web user (${WEB_OWNER}) has access to the coral device.
    On my ubuntu system, I needed to do:
        sudo usermod -a -G plugdev www-data
    --------------------------------------------------------------------
EOF
fi

if [ "${HOOK_CONFIG_UPGRADE}" == "yes" ] 
then
    echo
    echo "Creating a migrated objectconfig if required"
    ./tools/config_upgrade.py -c "${TARGET_CONFIG}/objectconfig.ini" 
else 
    echo "Skipping hook config upgrade process"
fi


echo
echo "*** Please remember to start the Event Server after this update ***" 
