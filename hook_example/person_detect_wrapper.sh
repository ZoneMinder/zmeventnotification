#!/bin/bash

# When invoked by zmeventnotification.pl it will be passed:
# $1 = eventId that triggered an alarm
# $2 = monitor ID of monitor that triggered an alarm
# $3 = monitor Name of monitor that triggered an alarm

# This will only work with the changes committed to index.php in this PR: https://github.com/ZoneMinder/zoneminder/pull/2231
# Given an event ID, it fetches a frame with maximum score so far (can also be used for in progress recordings

# Logic:
# This script is invoked by zmeventnotification is you've specified its location in the hook= variable of zmeventnotification.pl
# It will basically download an image from the current event being recorded and pass it to a python script that will actually do person detection

# By default, the image that has the "maximum score so far" will be downloaded. If you really want to download the first image that triggered motion
# then change the FID value below as described in the comments


# --------- You will need to change these ------------
PORTAL="https://yourserver/zm"
USERNAME=admin
PASSWORD=yourpassword
PERSON_DETECTION_SCRIPT="/usr/bin/detect.py" # path to detection script 
IMAGE_PATH="/tmp/person" # make sure this exists and WRITEABLE by www-data (or apache)

# --------- You *may* need to change these ------------
WGET="/usr/bin/wget"
#FID=26   # Set this to pre-event image count + 1 if you want the actual frame that triggered the alarm
FID="snapshot" # Use this if you want to analyze the frame with the maximum score

WILL_SNOOZE=0 # if 1 will wait for SNOOZE_DURATION seconds before it grabs a frame. 
SNOOZE_DURATION=2


_URL="${PORTAL}/index.php?view=image&eid=$1&fid=${FID}&width=800&username=${USERNAME}&password=${PASSWORD}"

if [ "${WILL_SNOOZE}" = "1" ]; then
    # let's sleep a bit to wait for ZM to write frames to disk for the current event
    sleep ${SNOOZE_DURATION}
fi

#get the actual image
${WGET} "${_URL}" --no-check-certificate -O "${IMAGE_PATH}/$1.jpg"  >/dev/null 2>&1

RESULTS=`${PERSON_DETECTION_SCRIPT}  --image ${IMAGE_PATH}/$1.jpg | grep "person detected"`

_RETVAL=1
# The script needs  to return a 0 for success (person detected) or 1 for failure (no person)
if [ "${RESULTS}" = "person detected" ]; then
    #echo "$3:${RESULTS}"
    echo "${RESULTS}"
   _RETVAL=0 
fi
exit ${_RETVAL}
