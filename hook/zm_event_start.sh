#!/bin/bash

trap 'cleanup' SIGINT SIGTERM
# Handle situation of ZM terminates while this is running
# so notifications are not sent
cleanup() {
   # Don't echo anything here
   exit 1
}


# change these to the path of the object detection config file and the path to where ZMES is installed
config_file="/etc/zm/objectconfig.yml"
zmes_dir="/var/lib/zmeventnotification"
# ENVIRONMENT VARIABLES USED BY NEO ZMES (WIP)
[ -n "$ZMES_CONFIG_FILE" ] && config_file="$ZMES_CONFIG_FILE"
[ -n "$ZMES_INSTALL_DIR" ] && zmes_dir="$ZMES_INSTALL_DIR"

docker=''
live=''
debug=''
bare_debug=''
eventpath=''
mid=''
eid=''
name=''
reason=''
print_usage() {
    echo "Usage: $0 [options]"
    echo "Non-Positional Options (-dDblh):"
    echo "  -h          Print this help"

    echo "  -d          Debug mode (Console output)"
    echo "  -b          \"Bare\" debug mode (No console output)"
    echo "  -l          Live mode (From Perl daemon)"
    echo "  -D          Run in docker mode"
    echo ""
    echo "Positional Options (-m 2 -e 321123 -n \"Back Yard\" -r \"Motion\"):"
    echo "  -m          Monitor ID"
    echo "  -e          Event ID"
    echo "  -n          Monitor name"
    echo "  -r          Event reason"
    echo "  -p          Path to event on disk"
    echo "  -c          Path to config file (default: $config_file)"
    echo "  -z          Path to ZMES Install dir (default: $zmes_dir)"
}

while getopts ":Dlhdbp:m:e:n:r:c:y:" opt
do
  case "$opt" in
    "h") print_usage; exit 0 ;;
    "D") docker='--docker' ;;
    "l") live='--live' ;;
    "d") debug='--debug' ;;
    "b") bare_debug='--baredebug' ;;
    "c") config_file=$OPTARG ;;
    "p") eventpath="$OPTARG" ;;
    "m") mid="$OPTARG" ;;
    "e") eid="$OPTARG" ;;
    "n") name="$OPTARG" ;;
    "r") reason="$OPTARG" ;;
    "y") zmes_dir="$OPTARG" ;;

    "?") print_usage >&2; exit 1 ;;
  esac
done

if [[ -z "$mid" ]]; then
      DETECTION_SCRIPT=("${zmes_dir}/bin/zm_detect.py" --eventid "$eid" --config "${config_file}"  --reason "${reason}" --event-type start  --eventpath "${eventpath}" "$docker" "$bare_debug" "$debug" "$live")
elif [[ -n "$mid" ]]; then
       DETECTION_SCRIPT=("${zmes_dir}/bin/zm_detect.py" --monitor-id "$mid" --eventid "$eid" --config "${config_file}"  --reason "${reason}" --event-type start  --eventpath "${eventpath}" "$docker" "$bare_debug" "$debug" "$live")
fi
# this is why the python script prints out the detection with 'detected:' in the string somewhere
RESULTS=$("${DETECTION_SCRIPT[@]}" | grep "detected:")
_RET_VAL=1
# The script needs to return a 0 for success (detected) or 1 for failure (not detected)
[[ -n "${RESULTS}" ]] && _RET_VAL=0
echo "${RESULTS}"
exit "${_RET_VAL}"