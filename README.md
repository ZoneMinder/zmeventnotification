
# Note
All credit goes to the original author @pliablepixels. Please see https://github.com/pliablepixels

Docker Images 
------------------
###EXPERIMENTAL!!

I have released working docker images for the following:

- [zoneminder-base](https://ghcr.io/baudneo/zoneminder-base) - ZM without ES - forked from zoneminder-containers with the intention to add LXC support as host.
- [eventserver-mlapi](https://ghcr.io/baudneo/eventserver-mlapi) - ZM with ES configured to communicate with the GPU/TPU accelerated MLAPI image
- [mlapi_cudnn-base](https://ghcr.io/baudneo/mlapi_cudnn-base) - MLAPI with CUDA/cuDNN and TPU support (ALL MODELS WORK)
Ongoing work is happening to allow zoneminder-* or eventserver-* images to run on an unprivileged LXC host. Currently only the mlapi_cudnn-* images work inside of unprivileged LXC (Docker running inside an LXC)

MAJOR CHANGES
---
- ZMEventnotification is now configured using YAML syntax (be aware zmeventnotification.yml and secrets.yml are still needed to configure the ES Perl daemon script! the object detection is technically an addition to the ES)
- The way the config is processed as a whole, it was designed with [MLAPI](https://github.com/zoneminder/mlapi) more in mind. It hashes the config and secrets file and based on if either file has changed, MLAPI will use the cached config or rebuild. This is for performance.
- !SECRETS are now {[secrets]} - allows embedding secrets into a substring or nested data structures inside the configuration files.
- (see note) - MLAPI and ZMES now communicate dynamically using weighted 'routes'. ZM API credentials are encrypted by Python cryptography.Fernet symmetrical key encryption to be transported to MLAPI (Many ZMES instances can request detections from 1 MLAPI instance)
- PERFORMANCE - I made many, many changes based on becoming more performant. There is logic for live and past events, the frame buffer is smarter and tries to handle out of bound frame calls or errors gracefully to recover instead of erring. Many tasks are now Threaded.
- Animations (see GIF below)- The first few frames of the animation is now the labeled image that is objdetect.jpg, they are faster, there is an option to add a timestamp onto the animation frames (useful if you save events as mp4)
- Pushover python add-on - I was trying to make notifications as fast as possible and settled on pushover, GOTIFY is faster but has less features. I use both as gotify is basically instant but pushover has a viewable image in the android drop down notifications.
- Custom push script - Added a gotify example of a shell script that ZMES runs with some arguments. You can build any notification service message you want if you follow the example and swap out the pertinent parts for your provider
- MQTT python add-on - Send MQTT data to a MQTT broker (has the ability to send the objdetect.jpg .gif using MQTT - Home Assistant MQTT Camera)
- Home Assistant sensors to control pushover notifications - You can create a 'Toggle Helper' which is an on/off switch and a 'Input Text Helper' which you can use to set a 'cool down' period between pushover notifications (configurable per monitor). If you do not use HA, there is a configurable option 'push_cooldown' for cooldowns between notifications.
- Pushover 'EMERGENCY' notifications - Persistent notifications with the ability to keep notifying the user until the user has acknowledged the notification. I added this functionality because I missed an alert early in the morning when a thief was prowling. Now my Android phone screams at me using the 'alarm' channel and by-passes 'Do Not Disturb' if configured to do so.

** NOTE: The way a MLAPI detection works now is the requesting ZMES instance will dump its creds into a dictionary which is then encrypted (key and value). The name of the current route is the only data in the credential dump that is not encrypted (this is so MLAPI 
can look in its config to find a matching encryption key based on the route name). ZMES sends MLAPI the detection request along with its already logged in and verified JWT Auth token, this saves MLAPI from having to log into the API to ask for it's own JWT. MLAPI will work through the detections and at the end it will send the detection data back as well as the matching image (when ZMES receives the response from mlapi it does not need to ask the API for the matching frame! more time saved!)

Example GIF - objdetect.jpg has polygon zone, labels, confidence and model names drawn on top. The timestamp is from ZM as I am using 'frames' (jpeg) storage instead of video passthrough that creates mp4s.

<img src="https://github.com/baudneo/zmeventnotification/blob/master/screenshots/improved_animations.gif" width="300px"/>

What
----
The Event Notification Server sits along with ZoneMinder and offers real time notifications, support for push notifications as well as Machine Learning powered recognition.
As of today, it supports:
* YOLO/Tiny YOLO via OpenCV DNN API (CPU/GPU)
* HOG (deprecated)
* coral USB EdgeTPU
* Face detections using TPU (Detection only, no recognition. Chain with DLib for recognition)
* Face detection/recognition using DLib (CPU/GPU)
* Deep license plate recognition - local ALPR binary or cloud providers (CPU/GPU)

*More algorithms may be added in the future*

Documentation
-------------
- View install.sh to customize install dir and options.
- Article walk through of installing ZM, neo ZMES and compiling OpenCV, DLib and ALPR with GPU support [here](https://medium.com/@baudneo/install-zoneminder-1-36-x-6dfab7d7afe7)

**These are the original install instructions**
- Documentation, including installation, FAQ etc.are [here for the latest stable release](https://zmeventnotification.readthedocs.io/en/stable/) and [here for the master branch](https://zmeventnotification.readthedocs.io/en/latest/)
- Always refer to the [Breaking Changes](https://zmeventnotification.readthedocs.io/en/latest/guides/breaking.html) document before you upgrade.


Requirements
-------------
- Python 3.6 or above (f-strings)
- OpenCV 4.2.0 or above (4.3.x+ for YOLO v4) [4.5.4+ recommended]
- ZoneMinder 1.34+ that is using JWT auth tokens (basic auth not recommended and may not be supported properly; untested ATM)

Screenshots
------------

Click each image for larger versions. Some of these images are from other users who have granted permission for use
###### (permissions received from: Rockedge/ZM Slack channel/Mar 15, 2019)

<img src="https://github.com/zoneminder/zmeventnotification/blob/master/screenshots/person_face.jpg" width="300px" /> <img src="https://github.com/baudneo/zmeventnotification/blob/master/screenshots/delivery.jpg" width="300px" /> <img src="https://github.com/baudneo/zmeventnotification/blob/master/screenshots/car.jpg" width="300px" /> <img src="https://github.com/baudneo/zmeventnotification/blob/master/screenshots/alpr.jpg" width="300px" />


