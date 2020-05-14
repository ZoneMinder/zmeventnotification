#!/usr/bin/python3

version = 0.1

# This script send analyized events over to an ftp server
# It was built to be used with home assistant.
# The objective is to use zoneminder to do person detection
# from video streams and then FTP the files over to home assistant.
# On Home assistant these files can be monitored via a file watcher
# Automations can then include the detection of a person in their
# to impact the action.  I'm using it look for people in the house
# should window or door sensors go off.


# Arguments passed
# ARG1 = event ID
# ARG2 = monitor ID
# ARG3 = monitor name
# ARG4 = Alarm cause
# ARG5 = type of event (event_start or event_end)
# ARG6 (Optional) = image path

import sys
from datetime import datetime
#import requests
import pyzm.ZMLog as zmlog
import os
import ftplib


# ES passes the image path, this routine figures out which image
# to use inside that path
def get_image(path, cause):
    # as of Mar 2020, pushover doesn't support
    # mp4
    if os.path.exists(path+'/objdetect.gif'):
        return path+'/objdetect.gif'
    elif os.path.exists(path+'/objdetect.jpg'):
        return path+'/objdetect.jpg'
    prefix = cause[0:2]
    if prefix == '[a]':
        return path+'/alarm.jpg'
    else:
        return path+'/snapshot.jpg'

# Simple function to read variables from secret file
def read_secrets(config='/etc/zm/secrets.ini'):
    from configparser import ConfigParser
    secrets_object = ConfigParser(interpolation=None)
    secrets_object.optionxform=str
    zmlog.Debug(1,'eid:{} Reading secrets from {}'.format(eid,config))
    with open(config) as f:
        secrets_object.read_file(f)
    return secrets_object._sections['secrets']

# -------- MAIN ---------------
zmlog.init(name='zmeventnotification_ftp')
zmlog.Info('--------| FTP Plugin v{} |--------'.format(version))

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
fname = None

if len(sys.argv) == 7:
    image_path =  sys.argv[6]
    fname=get_image(image_path, cause)

    zmlog.Debug (1,'eid:{} - {} Image to be used is: {}'.format(eid,event_type,fname))


# read parameters from secrets
secrets = read_secrets()
passwd = secrets.get('FTP_PASSWORD')
user = secrets.get('FTP_USERNAME')
server = secrets.get('FTP_SERVER')
careaboutlist = secrets.get('FTP_CAREABOUT').split(',')

zmlog.Debug(1,"eid:{} FTP to {} as {}".format(eid,server,user))

#Build the FTP command and file path
preExt,fileExt= os.path.splitext(fname)

reason = None
for item in careaboutlist:
    if item in cause:
        reason = item
        break

if not reason:
    exiti()

#if 'person' in cause:
#    reason = 'person'
#elif 'car' in cause:
#    reason = 'car'
#else:
#    reason = 'unk'

ftpcmd = 'STOR /share/' + mname + '/' + reason + '-' + datetime.now().strftime('%x-%X').replace('/','-',3) + fileExt

# create FTP session and execute command to store file
session = ftplib.FTP(server,user,passwd)
file = open(fname,'rb')                         # file to send
zmlog.Info("eid:{} FTP cmd: {}".format(eid,ftpcmd))
session.storbinary(ftpcmd, file)     # send the file
file.close()                                    # close file and FTP
session.quit()

zmlog.Debug(1,"eid:{} FTP done".format(eid))
zmlog.Info("eid:{} FTP done".format(eid))
zmlog.close()
