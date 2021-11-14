#!/usr/bin/env bash
# CREDIT TO ZM FORUM USER 'juan11perez' for the base of this script for gotify

# You dont have to send this notification to gotify, this is just an example of how to use the ARGS that are passed
# to whatever script you assign to 'custom_pushh_script' in objectconfig.yml

# Arguments passed
# ARG1 = event ID
# ARG2 = monitor ID
# ARG3 = monitor name
# ARG4 = Alarm cause
# ARG5 = type of event (event_start or event_end)
# ARG6 is the AUTH token (the token starts with 'token=', so dont put token= before ${ZM_TOKEN})
# ARG7 is the path to the image (Optional)

# If you configured push_user and push_pass in objectconfig then the token will be for that user.
# If you did not configure push_user it will pass you the token that ZMES is using (not recommended).
# I recommend making a ZM API user with VIEW privileges and using that for push_user and push_pass.

ZM_TOKEN=${6}
EVENT_ID=${1}
#EVENT_ID=`echo ${6} | awk -F'/' '{ print $8 }'`
#MESSAGE=`echo ${4} | sed -e 's/.*] \(.*\)Motion.*/\1/'`
CAMERA=$3
MESSAGE="$4"
GOTI_HOST='http://localhost:8080'
GOTI_TKN=''
# I may pass the ZM API portal as an ARG in future. I cant see a reason to alter it to anything else. You can always
# override it if you want!
ZM_PORTAL='https://zm.EXAMPLE.com/zm'
# CONNKEY is more for controlling the stream once it is already streaming (pause, FF, RW, etc.)
CONNKEY=${RANDOM}${RANDOM}

# I have embedded a link into the notification itself to click that allows you to view the event in a browser
# Just like the pushover notifications.
# *** NOTE *** You can embed the actual event right into the notification and it will play INSIDE OF THE GOTIFY WEB APP
# the android app will not be able to see the embedded event :(
# Here is a message that that will embed the event into the notification and play the event in the gotify web app ->
# (Your zm instance must be accessible by gotify for it to grab the image / event

#      \"message\": \"${MESSAGE^}\n\n![EMBEDDED EVENT](${ZM_PORTAL}/cgi-bin/nph-zms?mode=jpeg&scale=${SCALE}&maxfps=${MAXFPS}&buffer=${BUFFER}&replay=${REPLAY}&event=${EVENT_ID}&connkey=${CONNKEY}&${ZM_TOKEN})\n\n![Camera Image](${ZM_PORTAL}/index.php?view=image&eid=${EVENT_ID}&fid=${FRAMETYPE}&popup=1&${ZM_TOKEN})\",

# Try playing with these settings if you want. I found these to be a good base line.
SCALE=50
MAXFPS=15
BUFFER=1000
REPLAY=single
# objdetect - will grab GIF if it exists, if not it will grab JPG  ** This is the recommended **
# objdetect_mp4 - grabs MP4 if it exists
# objdetect_gif - grabs GIF if it exists
# objdetect_jpg - grabs JPG if it exists
# 123 - grabs frame 123
FRAMETYPE=objdetect
# -S with --silent will report back errors
PUSH_SCRIPT=(
  curl --silent -S --request POST \
  --url "${GOTI_HOST}/message?token=${GOTI_TKN}" \
  --header 'content-type: application/json' \
  --data "{
      \"title\": \"${CAMERA} Camera (${2}) - Event: ${1}\",
      \"message\": \"${MESSAGE}\n\n[View event in browser](${ZM_PORTAL}/cgi-bin/nph-zms?mode=jpeg&scale=${SCALE}&maxfps=${MAXFPS}&buffer=${BUFFER}&replay=${REPLAY}&event=${EVENT_ID}&connkey=${CONNKEY}&${ZM_TOKEN})\n\n![Camera Image](${ZM_PORTAL}/index.php?view=image&eid=${EVENT_ID}&fid=${FRAMETYPE}&popup=1&${ZM_TOKEN})\",
      \"priority\": 6,
        \"extras\": {
      \"client::display\": { \"contentType\": \"text/markdown\"}
  }
}"
)

# 'detected: will be in the successful output of gotify' response, if gotify replies with success this will catch it
RESULTS=$("${PUSH_SCRIPT[@]}" | grep "detected:")

_RET_VAL=1
# If you want the ZMES logs to say "custom push script SUCCESS'
# The script needs to return a 0, if it returns anything else the logger will record a failure even if your script was successful
# it will not affect the ZMES logic in anyway it is just for logging purposes.
# if grep found what we want then it is a success
[[ -n "${RESULTS}" ]] && _RET_VAL=0
# This echos to stdout so that the python script can catch it and log success or failure
echo "${_RET_VAL}"
exit "${_RET_VAL}"
