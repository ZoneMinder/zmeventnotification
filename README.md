
# *** This is the 'neo-ZMES' forked version! ***

# Note
All credit goes to the original author @pliablepixels. Please see https://github.com/pliablepixels
I taught myself python to work on this project, I am learning git, etc. Please forgive the terrible commits.

Please be aware that the 'neo' versions are NOT compatible with the source repos. The module structure is different, functions and args are different and processing the configs are a completely different syntax and structure. My goal is to add some more options for power users and speed things up. In my personal testing I can say that I have blazing fast detections compared to the source repos. Gotify is basically instant as long as the app is not battery optimized (I am unaware of if gotify has an iOS app).

I am actively taking enhancement requests for new features and improvements.

MAJOR CHANGES
---
- The 'hook' (object detection) part of ZMEventnotification is now configured using YAML syntax (be aware zmeventnotification.ini and secrets.ini are still needed to configure the ES Perl daemon script! the object detection is technically an addition to the ES)
- !SECRETS are now {[secrets]} - allows embedding secrets into a substring or nested data structures inside the configuration files.
- (see note) - MLAPI and ZMES now communicate dynamically using weighted 'routes'. ZM API credentials are encrypted by Python cryptography.Fernet symmetrical key encryption to be transported to MLAPI (Many ZMES instances can request detections from 1 MLAPI instance)
- PERFORMANCE - I made many, many changes based on becoming more performant. There is logic for live and past events, the frame buffer is smarter and tries to handle out of bound frame calls or errors gracefully to recover instead of erring. Many tasks are now Threaded.
- Animations (see bottom of page)- The first few frames of the animation is now the labeled image that is objdetect.jpg, they are faster, there is an option to add a timestamp onto the animation frames (useful if you save events as mp4)
- Pushover python add-on - I was trying to make notifications as fast as possible and settled on pushover, GOTIFY is faster but has less features. I use both as gotify is basically instant but pushover has a viewable image in the android drop down notifications.
- custom push script - Added a gotify example of a shell script that ZMES runs with some arguments. You can build any notification service message you want if you follow the example and swap out the pertinent parts for your provider
- MQTT python add-on - Send MQTT data to a MQTT broker (has the ability to send the objdetect.jpg .gif using MQTT - Home Assistant MQTT Camera)

** NOTE: The way a MLAPI detection works now is the requesting ZMES instance will dump its creds into a dictionary which is then encrypted (key and value). The name of the current route is the only data in the credential dump that is not encrypted (this is so MLAPI 
can look in its config to find a matching encryption key based on the route name). ZMES sends MLAPI the detection request along with its already logged in and verified JWT Auth token, this saves MLAPI from having to log into the API to ask for it own JWT. MLAPI will work theough the detections and at the end it will now send the detection data back as well as the matching image (now when ZMES receives the resposnse from mlapi it does not need to ask the API for the matching frame! more time saved!)

Project Map
---
Removing the 'local' aspect from ZMEventnotification. What I mean is that at the moment when you first install the ES and its 'hooks' (object detection), there is the ability to run detections using the script itself instead of sending an HTTP request to mlapi.
 MLAPI will be the DEFAULT way to run object detection. MLAPI will also try and default to unix sockets for communication with ZMES when MLAPI and ZMES are on the same host.

MLAPI keeps the ML models loaded into memory instead of having to load the models every single detection. This is a huge performance boost and I do not see the need to keep the 'local' aspect of ZMES around. MLAPI will be installed alongside ZMEventnotification server as the default way to process detections and will retain the ability to be installed by itself (NO ZMES or ZM on same host, mlapi still needs pyzm)

Pydantic models with validators to validate the configs and data (I have started to move MLAPI over to Pydantic models)

FastAPI rewrite instead of Flask/bjoern - I may have 2 separate branches that I will maintain to have the option of either or. I do not think that moving MLAPI to FastAPI will get many benefits as the bottlenecks for ML are the hardware.

** Adding support for other types of model frameworks (Tensorflow and PyTorch would be priority with other frameworks added later)

** Exploring possibility of using 2+ TPU's to run object detection. I dont have an m.2 TPU to play with but eventually the goal is to add support for them.

** Home Assistant integration - Possibility of integrating with OVH or other home automation systems


What
----
The Event Notification Server sits along with ZoneMinder and offers real time notifications, support for push notifications as well as Machine Learning powered recognition.
As of today, it supports:
* detection of 80 types of objects (persons, cars, etc.) - COCO
* face detections using TPU
* face detection/recognition using DLib
* deep license plate recognition - local ALPR binary or cloud providers

I will add more algorithms over time.

Documentation
-------------
- Article walk through of installing ZM, neo ZMES and compiling OpenCV, DLib and ALPR with GPU support [here](https://medium.com/@baudneo/install-zoneminder-1-36-x-6dfab7d7afe7)

These are the original install instructions
- Documentation, including installation, FAQ etc.are [here for the latest stable release](https://zmeventnotification.readthedocs.io/en/stable/) and [here for the master branch](https://zmeventnotification.readthedocs.io/en/latest/)
- Always refer to the [Breaking Changes](https://zmeventnotification.readthedocs.io/en/latest/guides/breaking.html) document before you upgrade.

3rd party dockers 
------------------
I don't maintain docker images, so please don't ask me any questions about docker environments. There are others who maintain docker images. 
Please see [this link](https://zmeventnotification.readthedocs.io/en/latest/guides/install.html#rd-party-dockers)

Requirements
-------------
- Python 3.6 or above
- OpenCV 4.2.0 or above
- ZoneMinder 1.34.3+ that is using JWT auth tokens (basic auth not recommended and may not be supported properly, basically its untested ATM for basic auth)

Screenshots
------------

Click each image for larger versions. Some of these images are from other users who have granted permission for use
###### (permissions received from: Rockedge/ZM Slack channel/Mar 15, 2019)

<img src="https://github.com/baudneo/zmeventnotification/blob/master/screenshots/person_face.jpg" width="300px" /> <img src="https://github.com/baudneo/zmeventnotification/blob/master/screenshots/delivery.jpg" width="300px" /> <img src="https://github.com/baudneo/zmeventnotification/blob/master/screenshots/car.jpg" width="300px" /> <img src="https://github.com/baudneo/zmeventnotification/blob/master/screenshots/alpr.jpg" width="300px" />
<img src="https://github.com/baudneo/zmeventnotification/blob/master/screenshots/improved_animations.gif" width="300px"/>.

