#!/bin/bash

# When invoked by zmeventnotification.pl it will be passed:
# $1 = eventId that triggered an alarm
# $2 = monitor ID of monitor that triggered an alarm
# $3 = monitor Name of monitor that triggered an alarm


s
# Only tested with ZM 1.32. May or may not work with older versions
# Needs [this updated file](https://github.com/ZoneMinder/zoneminder/blob/master/web/index.php) 
# to pull images (merged on Oct 9, 2018 so you may need to pull manually if your build is older)

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

# Enable this if you want fast but inaccurate HOG
#DETECTION_SCRIPT="/usr/bin/detect_hog.py" # path to detection script 

# Enable these if you want slower but more accurate DNN
# If you use YOLOv3, you will need to modify these too
YOLOV3_CONFIG="/var/detect/models/yolov3/yolov3.cfg"
YOLOV3_WEIGHTS="/var/detect/models/yolov3/yolov3.weights"
YOLOV3_LABELS="/var/detect/models/yolov3/yolov3_classes.txt"
DETECTION_SCRIPT="/usr/bin/detect_yolo.py -c ${YOLOV3_CONFIG} -w ${YOLOV3_WEIGHTS} -l ${YOLOV3_LABELS} " # path to detection script 

IMAGE_PATH="/var/detect/images" # make sure this exists and WRITEABLE by www-data (or apache)

# If you only want to detect persons, put in "person:" here. If you are using detect_yolo, 
# just making it "detected:" will detect all categories in https://github.com/arunponnusamy/object-detection-opencv/blob/master/yolov3.txt

# If you only want persons, make this person (or any other label class)
#DETECT_PATTERN="detected:"
DETECT_PATTERN="(person|car)"

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

RESULTS=`${DETECTION_SCRIPT}  --image ${IMAGE_PATH}/$1.jpg | grep "detected:"`

_RETVAL=1
# The script needs  to return a 0 for success ( detected) or 1 for failure (not detected)
if [[ "${RESULTS}" =~ ${DETECT_PATTERN} ]]; then
   _RETVAL=0 
fi
echo ${RESULTS}
exit ${_RETVAL}
