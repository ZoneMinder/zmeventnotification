#!/bin/bash

#-----------------------------------------------------
# Install script for the EventServer and the 
# machine learning hooks
#
# /install.sh --help
#
# Note that this doesn't install all the event server
# dependencies. You still need to follow the README
#
# It does however try to install all the hook dependencies
#
#-----------------------------------------------------

# --- Change these if you want --

PYTHON=python3
PIP=pip3

# Models to install
# If you don't want them, pass them as variables to install.sh
# example: sudo INSTALL_YOLO=no ./install.sh
INSTALL_YOLO=${INSTALL_YOLO:-yes}
INSTALL_TINYYOLO=${INSTALL_TINYYOLO:-yes}
INSTALL_CSPN=${INSTALL_CSPN:-yes}


TARGET_CONFIG='/etc/zm'
TARGET_DATA='/var/lib/zmeventnotification'
TARGET_BIN_ES='/usr/bin'
TARGET_BIN_HOOK='/var/lib/zmeventnotification/bin'

WGET=$(which wget)
WEB_OWNER_FROM_PS=$(ps xao user,group,comm | grep -E '(httpd|hiawatha|apache|apache2|nginx)' | grep -v whoami | grep -v root | head -n1 | awk '{print $1}')
#WEB_OWNER='www-data' # uncomment this if the above mechanism fails

WEB_GROUP_FROM_PS=$(ps xao user,group,comm | grep -E '(httpd|hiawatha|apache|apache2|nginx)' | grep -v whoami | grep -v root | head -n1 | awk '{print $2}')
#WEB_GROUP='www-data' # uncomment if above line fails
# make this empty if you don't want backups
MAKE_CONFIG_BACKUP='--backup=numbered'

# --- end of change these ---

# set default values 
# if we have a value from ps use it, otherwise look in env
WEB_OWNER=${WEB_OWNER_FROM_PS:-$WEB_OWNER}
WEB_GROUP=${WEB_GROUP_FROM_PS:-$WEB_GROUP}
# if we don't have a value from ps or env, use default
WEB_OWNER=${WEB_OWNER:-www-data}
WEB_GROUP=${WEB_GROUP:-www-data}
WGET=${WGET:-/usr/bin/wget}


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
    echo "Your webserver group seems to be ${WEB_GROUP}"
    echo "wget is at ${WGET}"
    echo
    echo "Install Event Server: ${INSTALL_ES}"
    echo "Install Event Server config: ${INSTALL_ES_CONFIG}"
    echo "Install Hooks: ${INSTALL_HOOK}"
    echo "Install Hooks config: ${INSTALL_HOOK_CONFIG}"
    echo
    [[ ${INSTALL_ES} != 'no' ]] && echo "The Event Server will be installed to ${TARGET_BIN_ES}"
    [[ ${INSTALL_ES_CONFIG} != 'no' ]] && echo "The Event Server config will be installed to ${TARGET_CONFIG}"

    [[ ${INSTALL_HOOK} != 'no' ]] && echo "The hook files will be installed to ${TARGET_DATA} sub-folders"
    [[ ${INSTALL_HOOK_CONFIG} != 'no' ]] && echo "The hook config files will be installed to ${TARGET_CONFIG}"

    echo
    echo "Models that will be checked/installed:"
    echo "Yolo: ${INSTALL_YOLO}"
    echo "TinyYolo: ${INSTALL_TINYYOLO}"
    echo "CSPN: ${INSTALL_CSPN}"

    echo
     [[ ${INTERACTIVE} == 'yes' ]] && read -p "If any of this looks wrong, please hit Ctrl+C and edit the variables in this script..."

}


# move proc for zmeventnotification.pl
install_es() {
    echo '***** Installing ES **********'
    mkdir -p "${TARGET_DATA}/push" 2>/dev/null
    install -m 755 -o "${WEB_OWNER}" -g "${WEB_GROUP}" zmeventnotification.pl "${TARGET_BIN_ES}" && 
            print_success "Completed, but you will still have to install ES dependencies as per https://github.com/pliablepixels/zmeventnotification/blob/master/README.md#install-dependencies"  || print_error "failed"
    #echo "Done, but you will still have to manually install all ES dependencies as per https://github.com/pliablepixels/zmeventnotification#how-do-i-install-it"
}

# install proc for ML hooks
install_hook() {
    echo '*** Installing Hooks ***'
    mkdir -p "${TARGET_DATA}/bin" 2>/dev/null
    rm -fr  "${TARGET_DATA}/bin/*" 2>/dev/null

    mkdir -p "${TARGET_DATA}/images" 2>/dev/null
    mkdir -p "${TARGET_DATA}/mlapi" 2>/dev/null
    mkdir -p "${TARGET_DATA}/known_faces" 2>/dev/null
    mkdir -p "${TARGET_DATA}/unknown_faces" 2>/dev/null
    mkdir -p "${TARGET_DATA}/models/yolov3" 2>/dev/null
    mkdir -p "${TARGET_DATA}/models/tinyyolo" 2>/dev/null
    mkdir -p "${TARGET_DATA}/models/cspn" 2>/dev/null
    mkdir -p "${TARGET_DATA}/misc" 2>/dev/null
    echo "everything that does not fit anywhere else :-)" > "${TARGET_DATA}/misc/README.txt" 2>/dev/null
    

    if [ "${INSTALL_YOLO}" == "yes" ]
    then
      # If you don't already have data files, get them
      # First YOLOV3
      echo 'Checking for YoloV3 data files....'
      targets=('yolov3.cfg' 'yolov3_classes.txt' 'yolov3.weights')
      sources=('https://raw.githubusercontent.com/pjreddie/darknet/master/cfg/yolov3.cfg'
              'https://raw.githubusercontent.com/pjreddie/darknet/master/data/coco.names'
              'https://pjreddie.com/media/files/yolov3.weights')

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

    if [ "${INSTALL_TINYYOLO}" == "yes" ]
    then
      # Next up, TinyYOLO
      echo
      echo 'Checking for TinyYOLO data files...'
      targets=('yolov3-tiny.cfg' 'yolov3-tiny.txt' 'yolov3-tiny.weights')
      sources=('https://raw.githubusercontent.com/pjreddie/darknet/master/cfg/yolov3-tiny.cfg'
              'https://raw.githubusercontent.com/pjreddie/darknet/master/data/coco.names'
              'https://pjreddie.com/media/files/yolov3-tiny.weights')

      for ((i=0;i<${#targets[@]};++i))
      do
          if [ ! -f "${TARGET_DATA}/models/tinyyolo/${targets[i]}" ]
          then
              ${WGET} "${sources[i]}"  -O"${TARGET_DATA}/models/tinyyolo/${targets[i]}"
          else
              echo "${targets[i]} exists, no need to download"

          fi
      done
    fi

  if [ "${INSTALL_CSPN}" == "yes" ]
  then
    # Next up, CSPNet
    echo
    echo 'Checking for CSPNet data files...'
    print_warning 'Note, you need OpenCV >= 4.3 for CSPNet to work'
    targets=('csresnext50-panet-spp-original-optimal.cfg' 'coco.names')
    sources=('https://raw.githubusercontent.com/AlexeyAB/darknet/master/cfg/csresnext50-panet-spp-original-optimal.cfg'
             'https://raw.githubusercontent.com/pjreddie/darknet/master/data/coco.names'
            )

    for ((i=0;i<${#targets[@]};++i))
    do
        if [ ! -f "${TARGET_DATA}/models/cspn/${targets[i]}" ]
        then
            ${WGET} "${sources[i]}"  -O"${TARGET_DATA}/models/cspn/${targets[i]}"
        else
            echo "${targets[i]} exists, no need to download"

        fi
    done
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
    echo "Removing old version of zmes-hooks, if any"
    ${PY_SUDO} ${PIP} uninstall -y zmes-hooks  >/dev/null 2>&1
    ${PY_SUDO} ${PIP} install hook/ && print_opencv_message || print_error "python hooks setup failed"

    echo "Installing package deps..."
    echo "Installing gifsicle, if needed..."
    ${PY_SUDO} apt-get install gifsicle -qq

}


# move ES config files
install_es_config() {
    echo 'Replacing ES config file'
    install ${MAKE_CONFIG_BACKUP} -o "${WEB_OWNER}" -g "${WEB_GROUP}"  -m 644 zmeventnotification.ini "${TARGET_CONFIG}" && 
        print_success "config copied" || print_error "could not copy config"
    if [ ! -f "${TARGET_CONFIG}/secrets.ini" ]; then
     install ${MAKE_CONFIG_BACKUP} -o "${WEB_OWNER}" -g "${WEB_GROUP}"  -m 644 secrets.ini "${TARGET_CONFIG}" && 
        print_success "secrets copied" || print_error "could not copy secrets"
    fi
   


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
     have installed of opencv* and compiling OpenCV 4.2.x from source. 
     See https://zmeventnotification.readthedocs.io/en/latest/guides/hooks.html#opencv-install

    |----------------------------------------------------------------------|

EOF
}

# wuh
display_help() {
    cat << EOF
    
    $0 [-h|--help] [--install-es|--no-install-es] [--install-hook|--no-install-hook] [--install-config|--no-install-config] [--no-pysudo]

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

    for key in "${cmd_args[@]}"
    do
    case $key in
        -h|--help)
            display_help && exit
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

if [ "${INSTALL_CSPN}" == "yes" ] && [ ! -f "${TARGET_DATA}/models/cspn/csresnext50-panet-spp-original-optimal_final.weights" ]
    then
      print_important '*************************************************************'
      print_important 'You need to manually download CSPN weights'
      print_important 'NOTE: Please download https://drive.google.com/open?id=1_NnfVgj0EDtb_WLNoXV8Mo7WKgwdYZCc'
      print_important "And place it inside ${TARGET_DATA}/models/cspn"
      print_important '*************************************************************'

    fi

