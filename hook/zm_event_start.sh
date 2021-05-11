#!/bin/bash

trap 'cleanup' SIGINT SIGTERM

# Handle situation of ZM terminates while this is running
# so notifications are not sent
cleanup() {
   # Don't echo anything here
   exit 1
}

# When invoked by zmeventnotification.pl it will be passed:
# $1 = eventId that triggered an alarm
# $2 = monitor ID of monitor that triggered an alarm
# $3 = monitor Name of monitor that triggered an alarm
# $4 = cause of alarm 
# $5 = path to event store (if store_frame_in_zm is 1)



# Only tested with ZM 1.32.3+. May or may not work with older versions
# Logic:
# This script is invoked by zmeventnotification is you've specified its location in the hook= variable of zmeventnotification.pl


# change this to the path of the object detection config"
CONFIG_FILE="/etc/zm/objectconfig.ini"
COMMAND="/var/lib/zmeventnotification/bin/zm_detect.py --config \"${CONFIG_FILE}\""

[[ ! -z "${1}" ]] && COMMAND="${COMMAND} --eventid ${1}"
[[ ! -z "${2}" ]] && COMMAND="${COMMAND} --monitorid ${2}"
[[ ! -z "${4}" ]] && COMMAND="${COMMAND} --reason \"${4}\""
[[ ! -z "${5}" ]] && COMMAND="${COMMAND} --eventpath \"${5}\""


# use arrays instead of strings to avoid quote hell
DETECTION_SCRIPT=( "${COMMAND}" )
RESULTS=$("${DETECTION_SCRIPT[@]}" | grep "detected:")

_RETVAL=1
# The script needs  to return a 0 for success ( detected) or 1 for failure (not detected)
if [[ ! -z "${RESULTS}" ]]; then
   _RETVAL=0 
fi
echo ${RESULTS}
exit ${_RETVAL}
