#!/usr/bin/env bash
trap 'cleanup' SIGINT SIGTERM
cleanup() {
   exit 1
}

CONFIG_FILE="/etc/zm/objectconfig.yml"
ZMES_DIR="/var/lib/zmeventnotification"
# ENVIRONMENT VARIABLES USED BY NEO ZMES (WIP)
[ -n "$ZMES_CONFIG_FILE" ] && config_file="$ZMES_CONFIG_FILE"
[ -n "$ZMES_INSTALL_DIR" ] && zmes_dir="$ZMES_INSTALL_DIR"

# I am hoping the ZM dev team adds Monitor ID as ARG2
#MID=$2
EID=$1
DET_SCRIPT=("${ZMES_DIR}/bin/zm_detect.py" --eventid "${EID}" --config "${CONFIG_FILE}" --live --debug --event-type "start" --new)
# --monitor-id "${MID}")
DET_OUTPUT=$("${DET_SCRIPT[@]}")
echo "DET SCRIPT = ${DET_SCRIPT[*]}"
echo "DET OUTPUT = $DET_OUTPUT"
echo 0
exit 0