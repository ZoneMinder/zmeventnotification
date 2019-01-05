#!/bin/bash

# version: 2.0

# When invoked by zmeventnotification.pl it will be passed:
# $1 = eventId that triggered an alarm
# $2 = monitor ID of monitor that triggered an alarm
# $3 = monitor Name of monitor that triggered an alarm
# $4 = cause of alarm 



# Only tested with ZM 1.32.3+. May or may not work with older versions
# Logic:
# This script is invoked by zmeventnotification is you've specified its location in the hook= variable of zmeventnotification.pl
# It will basically download an image from the current event being recorded and pass it to a python script that will actually do person detection
# By default, it will download both first alarm and highest score images and check both. Change FID to change this logic



# --------- You will need to change these ------------
PORTAL="https://yourserver/zm"
USERNAME=admin
PASSWORD=yourpassword

DELETE_IMAGES="--delete" # comment this if you don't want to delete downloaded images
#DELETE_IMAGES=""

# Enable this if you want fast but inaccurate HOG
#DETECTION_SCRIPT="/usr/bin/detect_hog.py" # path to detection script 

# Enable these if you want slower but more accurate DNN

# If you use YOLOv3, you will need to modify these too
#takes around 4GB to load in memory
YOLOV3_CONFIG="/var/detect/models/yolov3/yolov3.cfg"
YOLOV3_WEIGHTS="/var/detect/models/yolov3/yolov3.weights"
YOLOV3_LABELS="/var/detect/models/yolov3/yolov3_classes.txt"

#Instead of the above config files, you can also use Tiny YOLOv3
#better than HOG, worse than YoloV3 as far as accuracy, but almost as fast as HOG
#takes around 1GB to load in memory
#YOLOV3_CONFIG="/var/detect/models/tinyyolo/yolov3-tiny.cfg"
#YOLOV3_WEIGHTS="/var/detect/models/tinyyolo/yolov3-tiny.weights"
#YOLOV3_LABELS="/var/detect/models/tinyyolo/yolov3-tiny.txt"

DETECTION_SCRIPT="/usr/bin/detect_yolo.py -c ${YOLOV3_CONFIG} -w ${YOLOV3_WEIGHTS} -l ${YOLOV3_LABELS} " # path to detection script 

IMAGE_PATH="/var/detect/images" # make sure this exists and WRITEABLE by www-data (or apache)

# If you only want to detect persons, put in "person:" here. If you are using detect_yolo, 
# just making it "detected:" will detect all categories in https://github.com/arunponnusamy/object-detection-opencv/blob/master/yolov3.txt

# If you only want persons, make this person (or any other label class)
# Note: This is a python regular expression, so if you change it, follow python reg exp guidelines
#DETECT_PATTERN=".*"
DETECT_PATTERN="(person|car)"

# --------- You *may* need to change these ------------
WGET="/usr/bin/wget"

# If you are using ZM 1.32.3 or above, you can use any of the modes below without any change.
# If you are however using ZM 1.32.2 or less, you need to also enable frames in your storage if you want
# to use anything besides snapshot

FID="bestmatch" # first try alarm, if it fails, try snapshot
#FID="alarm" # get first alarmed frame
#FID="snapshot" # Use this if you want to analyze the frame with the maximum score
#FID=26   # specific frame id

WILL_SNOOZE=0 # if 1 will wait for SNOOZE_DURATION seconds before it grabs a frame. 
SNOOZE_DURATION=2

if [ "${WILL_SNOOZE}" = "1" ]; then
    # let's sleep a bit to wait for ZM to write frames to disk for the current event
    sleep ${SNOOZE_DURATION}
fi

#get the actual image

if [[ "${FID}" = "bestmatch" ]]; then
#get both alarm and snapshot
    _URL="${PORTAL}/index.php?view=image&eid=$1&fid=alarm&width=800&username=${USERNAME}&password=${PASSWORD}"
    ${WGET} "${_URL}" --no-check-certificate -O "${IMAGE_PATH}/$1-alarm.jpg"  >/dev/null 2>&1
    _URL="${PORTAL}/index.php?view=image&eid=$1&fid=snapshot&width=800&username=${USERNAME}&password=${PASSWORD}"
    ${WGET} "${_URL}" --no-check-certificate -O "${IMAGE_PATH}/$1-snapshot.jpg"  >/dev/null 2>&1
    RESULTS=`${DETECTION_SCRIPT}  ${DELETE_IMAGES}  --bestmatch --image ${IMAGE_PATH}/$1.jpg --pattern "${DETECT_PATTERN}"| grep "detected:"`
else # only one image get
    _URL="${PORTAL}/index.php?view=image&eid=$1&fid=${FID}&width=800&username=${USERNAME}&password=${PASSWORD}"
    ${WGET} "${_URL}" --no-check-certificate -O "${IMAGE_PATH}/$1.jpg"  >/dev/null 2>&1
    RESULTS=`${DETECTION_SCRIPT}  ${DELETE_IMAGES} --image ${IMAGE_PATH}/$1.jpg  --pattern "${DETECT_PATTERN}" | grep "detected:"`
fi



_RETVAL=1
# The script needs  to return a 0 for success ( detected) or 1 for failure (not detected)
if [[ ! -z "${RESULTS}" ]]; then
   _RETVAL=0 
fi
echo ${RESULTS}
exit ${_RETVAL}
