#!/usr/bin/python3

# This is a sample python script for sending notifications over pushover
# Write your own script to add a new push service, and modify 
# api_push_script in zmeventnotification.ini to invoke that script

# Example taken from https://support.pushover.net/i44-example-code-and-pushover-libraries#python

# Arguments passed
# ARG1 = event ID
# ARG2 = monitor ID
# ARG3 = monitor name
# ARG4 = Alarm cause 
# ARG5 = type of event (event_start or event_end)
# ARG6 (Optional) = image path

# ===============================================================
# MODIFY THESE
# ===============================================================

# Look at https://pushover.net/api and put anything you want here
# just don't add image, title and message as it gets automatically
# populated later

param_dict = {

    'token': 'YOUR PUSHOVER APP TOKEN',
    'user': 'YOUR PUSHOVER USER KEY',
    #'sound':'tugboat',
    #'priority': 0,
    # 'device': 'a specific device',
    # 'url':  'http://whateeveryouwant',
    # 'url_title': 'My URL title',

    
}




# ========== Don't change anything below here, unless you know what you are doing 

import sys
import datetime
import requests
import pyzm.ZMLog as zmlog
import os

# ES passes the image path, this routine figures out which image
# to use inside that path
def get_image(path, cause):
    if os.path.exists(path+'/objdetect.jpg'):
        return path+'/objdetect.jpg'
    prefix = cause[0:2]
    if prefix == '[a]':
        return path+'/alarm.jpg'
    else:
         return path+'/snapshot.jpg'


# -------- main 

zmlog.init(name='zmeventnotification_pushapi')

if len(sys.argv) < 6:
    zmlog.Error ('Missing arguments, got {} arguments, was expecting at least 6: {}'.format(len(sys.argv)-1, sys.argv))
    zmlog.close()
    exit(1)

eid = sys.argv[1]
mid = sys.argv[2]
mname = sys.argv[3]
cause = sys.argv[4]
event_type = sys.argv[5]
image_path = None
files = None

if len(sys.argv) == 7:
    image_path =  sys.argv[6]
    fname=get_image(image_path, cause)
    zmlog.Debug (1,'Image to be used is: {}'.format(fname))
    files = {
         "attachment": ("image.jpg", open(fname,"rb"), "image/jpeg")
    }


param_dict['title'] = '{} Alarm ({})'.format(mname,eid)
param_dict['message'] = cause
if event_type == 'event_end':
    param_dict['title'] = 'Ended:' + param_dict['title']

r = requests.post("https://api.pushover.net/1/messages.json", data = param_dict, files = files)
print(r.text)


zmlog.close()
