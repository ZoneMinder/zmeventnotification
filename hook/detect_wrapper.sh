#!/bin/bash

# When invoked by zmeventnotification.pl it will be passed:
# $1 = eventId that triggered an alarm
# $2 = monitor ID of monitor that triggered an alarm
# $3 = monitor Name of monitor that triggered an alarm
# $4 = cause of alarm 



# Only tested with ZM 1.32.3+. May or may not work with older versions
# Logic:
# This script is invoked by zmeventnotification is you've specified its location in the hook= variable of zmeventnotification.pl


# change this to the path of the object detection config"
CONFIG_FILE="/var/detect/config/objectconfig.ini"

DETECTION_SCRIPT="/usr/bin/detect_yolo.py --monitorid $2 --eventid $1 --config ${CONFIG_FILE}"
#DETECTION_SCRIPT="/usr/bin/detect_hog.py --monitorid $2 --eventid $1 --config ${CONFIG_FILE}"

RESULTS=`${DETECTION_SCRIPT}|grep "detected:"`
_RETVAL=1
# The script needs  to return a 0 for success ( detected) or 1 for failure (not detected)
if [[ ! -z "${RESULTS}" ]]; then
   _RETVAL=0 
fi
echo ${RESULTS}
exit ${_RETVAL}
