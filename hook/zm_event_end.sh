#!/bin/bash

trap 'cleanup' SIGINT SIGTERM

# Handle situation of ZM terminates while this is running
# so notifications are not sent
cleanup() {
   # Don't echo anything here
   exit 1
}

# When invoked by zmeventnotification.pl it will be passed:
# $1 = event Id that triggered an alarm
# $2 = monitor ID of monitor that triggered an alarm
# $3 = monitor Name of monitor that triggered an alarm
# $4 = cause of alarm
# $5 = 'live' - means a LIVE event for logic
# $6 = path to event store (if store_frame_in_zm is 1)



# Only tested with ZM 1.32.3+. May or may not work with older versions
# Logic:
# This script is invoked by zmeventnotification if you've specified its location in the hook= variable of zmeventnotification.yml


# change this to the path of the object detection config"
CONFIG_FILE="/etc/zm/objectconfig.yml"
ZMES_DIR="/var/lib/zmeventnotification"
LIVE=''
[[ -n "$5" ]] && [[ "$5" == '--live' ]] && LIVE='--live'
DOCKER=''
if [[ -n "$6" ]] && [[ "$6" == '--docker' ]]; then
  DOCKER='--docker'
  EVENT_PATH="$7"
  else
    EVENT_PATH="$6"
fi
REASON="$4"

# Pass the monitor ID so the api creation can be created in its own Thread - if no monitor ID is passed the system will
# create the api object, login and ask for the monitor ID based on the event ID (adds an extra 1-2 seconds to the
# response time) PASSING THE MONITOR ID SPEEDS THINGS UP!  SINCE MONITOR id AND --LIVE ARE PASSED WE CAN BE SURE THAT
# THE MONITOR ID HAS BEEN VERIFIED BEFOREHAND
# use arrays instead of strings to avoid quote hell
#if [[ -n "${2}" ]]; then
#   DETECTION_SCRIPT=("${ZMES_DIR}/bin/zm_detect.py" --monitor-id "$2" --eventid "$1" --config "${CONFIG_FILE}" --eventpath "${EVENT_PATH}" --reason "${REASON}" --event-type "start" "$LIVE" "$DOCKER")
#elif [[ -n "${1}" ]]; then
   DETECTION_SCRIPT=("${ZMES_DIR}/bin/zm_detect.py" --eventid "$1" --config "${CONFIG_FILE}" --eventpath "${EVENT_PATH}" --reason "${REASON}" --event-type "start" "$LIVE" "$DOCKER")
#fi
## this is why the python script prints out the detection with 'detected:' in the string somewhere
#RESULTS=$("${DETECTION_SCRIPT[@]}" | grep "detected:")
#
#_RET_VAL=1
## The script needs  to return a 0 for success ( detected) or 1 for failure (not detected)
#if [[ -n "${RESULTS}" ]]; then
#   _RET_VAL=0
#fi
#echo "${RESULTS}"
exit "${_RET_VAL}"
