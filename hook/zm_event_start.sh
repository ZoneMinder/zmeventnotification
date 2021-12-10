#!/bin/bash
# Only tested with ZM 1.32.3+. May or may not work with older versions (pliablepixels)
# Logic:
# This script is invoked by zmeventnotification if you've specified its location in the hook= variable of zmeventnotification.yml/.ini

# change these to the path of the object detection config file and the path to where ZMES is installed
CONFIG_FILE="/etc/zm/objectconfig.yml"
ZMES_DIR="/var/lib/zmeventnotification"
# ENVIRONMENT VARIABLES USED BY NEO ZMES (WIP)
[ -n "$ZMES_CONFIG_FILE" ] && CONFIG_FILE="$ZMES_CONFIG_FILE"
[ -n "$ZMES_INSTALL_DIR" ] && ZMES_DIR="$ZMES_INSTALL_DIR"
# ----------------------------------- DO NOT CHANGE BELOW ----------------------------------- #
trap 'cleanup' SIGINT SIGTERM
# Handle situation of ZM terminates while this is running
# so notifications are not sent
cleanup() {
   # Don't echo anything here
   exit 1
}
# When invoked by zmeventnotification.pl this script will be passed:
# $1 = event Id that triggered an alarm
# $2 = monitor ID of monitor that triggered an alarm
# $3 = monitor Name of monitor that triggered an alarm
# $4 = cause of alarm
# $5 = Could be '--live' - means a LIVE event for logic
# $6 = Could be --docker or path to event store (if store_frame_in_zm is 1)
# $ FINAL ARGUMENT = path to directory that holds event (EVENT PATH)

# Example ARGS
# 481 1 "Monitor-1" "All, Motion" --live --docker "/data/events/1/2021-12-07/481" --debug
REASON="$4"
LIVE=''
DOCKER=''
EVENT_PATH=''
if [[ -n "$5" ]]; then
  if [[ "$5" == '--live' ]]; then
    LIVE='--live'
  elif [[ "$5" == '--docker' ]]; then
    DOCKER='--docker'
  elif [[ "${5[1]}" == '/' ]]; then
    EVENT_PATH="$5"
  fi
  if [[ -n "$6" ]]; then
    if [[ "$6" == '--docker' ]]; then
    DOCKER='--docker'
      if [[ "${7[1]}" == '/' ]]; then
        EVENT_PATH="$7"
      elif [[ "${6[1]}" == '/' ]]; then
        EVENT_PATH="$6"
      fi
    fi
  fi
fi

dbg=''
[[ -n $(echo "$*" | grep "\(\s\?--debug\b\)") ]] && dbg='--debug'
[[ -n $(echo "$*" | grep "\(\s\?-d\b\)") ]] && dbg='--debug'

# Pass the monitor ID so the api creation can be created in its own Thread - if no monitor ID is passed the system will
# create the api object, login and ask for the monitor ID based on the event ID (adds an extra 1-2 seconds to the
# response time) PASSING THE MONITOR ID SPEEDS THINGS UP!  SINCE MONITOR ID AND --LIVE ARE PASSED WE CAN BE SURE THAT
# THE MONITOR ID HAS BEEN VERIFIED BEFOREHAND
# use arrays instead of strings to avoid quote hell
# checks for $1 and $2 are for when a user executes from CLI
if [[ -n "${2}" ]]; then
   DETECTION_SCRIPT=("${ZMES_DIR}/bin/zm_detect.py" --monitor-id "$2" --eventid "$1" --config "${CONFIG_FILE}" --eventpath "${EVENT_PATH}" --reason "${REASON}" --event-type "start" "$LIVE" "$DOCKER" "$dbg")
elif [[ -n "${1}" ]]; then
   DETECTION_SCRIPT=("${ZMES_DIR}/bin/zm_detect.py" --eventid "$1" --config "${CONFIG_FILE}" --eventpath "${EVENT_PATH}" --reason "${REASON}" --event-type "start" "$LIVE" "$DOCKER" "$dbg")
fi
# this is why the python script prints out the detection with 'detected:' in the string somewhere
RESULTS=$("${DETECTION_SCRIPT[@]}" | grep "detected:")

_RET_VAL=1
# The script needs to return a 0 for success (detected) or 1 for failure (not detected)
if [[ -n "${RESULTS}" ]]; then
   _RET_VAL=0
fi
echo "${RESULTS}"
exit "${_RET_VAL}"
