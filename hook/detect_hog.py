#!/usr/bin/python

# version: 3.0

# Please don't ask me questions about this script
# its a simple OpenCV person detection script I've proved as a sample 'hook' you can add to the notification server

# credit: https://www.pyimagesearch.com/2015/11/16/hog-detectmultiscale-parameters-explained/

# import the necessary packages
from __future__ import print_function
from imutils.object_detection import non_max_suppression
from imutils import paths
import numpy as np
import argparse
import imutils
import cv2
import datetime
import os
import re
import sys
import configparser
import urllib



def str2arr(str):
    return  [map(int,x.strip().split(',')) for x in str.split(' ')]

# main handler
# set up logging to syslog
import logging
import logging.handlers
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
handler = logging.handlers.SysLogHandler('/dev/log')
formatter = logging.Formatter('detect_hog:[%(process)d]: %(levelname)s [%(message)s]')
handler.formatter = formatter
logger.addHandler(handler)
 
# construct the argument parse and parse the arguments
ap = argparse.ArgumentParser()
ap.add_argument('-c', '--config', required=True, help='config file with path')
ap.add_argument('-e', '--eventid', required=True,  help='event ID to retrieve')
ap.add_argument('-m', '--monitor',  help='monitor id - needed for mask')
ap.add_argument('-t', '--time',  help='log time')

args,u = ap.parse_known_args()
args = vars(args)

# process config file
config_file = configparser.ConfigParser()
config_file.read(args['config'])

# parse config file into a dictionary with defaults
config={}
try:
    config['portal']=config_file['general'].get('portal','');
    config['user']=config_file['general'].get('user','admin');
    config['password']=config_file['general'].get('password','admin');
    config['image_path']=config_file['general'].get('image_path','/var/detect/images');
    config['frame_id']=config_file['general'].get('frame_id','snapshot');
    config['resize']=config_file['general'].get('resize','800');
    config['delete_after_analyze']=config_file['general'].get('delete_after_analyze','no');
    config['log_level']=config_file['general'].get('log_level','info');

    config['stride']=eval(config_file['hog'].get('stride','(4,4)'));
    config['padding']=eval(config_file['hog'].get('padding','(8,8)'));
    config['scale']=config_file['hog'].get('scale','1.05');
    config['mean_shift']=config_file['hog'].get('mean_shift','-1');

    if config['log_level']=='debug':
        logger.setLevel(logging.DEBUG)
    elif config['log_level']=='info':
        logger.setLevel(logging.INFO)
    elif config['log_level']=='error':
        logger.setLevel(logging.ERROR)

    # get the mask polygons for the supplied monitor
    if args['monitor']:
            if config_file.has_section('mask-'+args['monitor']):
                itms = config_file['mask-'+args['monitor']].items()
                if itms: logger.debug ('mask definition found for monitor:'+args['monitor'])
                a=[]
                for k,v in itms:
                    a.append(str2arr(v))
                    masks = np.asarray(a)
            else:
                logger.debug ('no mask found for monitor:'+args['monitor'])
                masks = np.asarray([])
    else:
        logger.error ('Ignoring masks, as you did not provide a monitor id')
        masks = np.asarray([])

except Exception,e:
    logger.error('Error parsing config:'+args['config'])
    logger.error('Error was:'+str(e))
    exit(0)


# now download image(s)
if config['frame_id'] == 'bestmatch':
    # download both alarm and snapshot
    filename1 = config['image_path']+'/'+args['eventid']+'-snapshot.jpg'
    filename2 = config['image_path']+'/'+args['eventid']+'-alarm.jpg'
    url = config['portal']+'/index.php?view=image&eid='+args['eventid']+'&fid=snapshot'+ \
          '&username='+config['user']+'&password='+config['password']
    urllib.urlretrieve(url,filename1)

    url = config['portal']+'/index.php?view=image&eid='+args['eventid']+'&fid=alarm'+ \
          '&username='+config['user']+'&password='+config['password']
    urllib.urlretrieve(url,filename2)
else:
    # only download one
    filename1 = config['image_path']+'/'+args['eventid']+'.jpg'
    filename2 = ''
    url = config['portal']+'/index.php?view=image&eid='+args['eventid']+'&fid='+config['frame_id']+ \
          '&username='+config['user']+'&password='+config['password']
    urllib.urlretrieve(url,filename1)


winStride = config['stride']
padding = config['padding']
meanShift = True if int(config['mean_shift']) > 0 else False

# initialize the HOG descriptor/person detector
hog = cv2.HOGDescriptor()
hog.setSVMDetector(cv2.HOGDescriptor_getDefaultPeopleDetector())

logger.info ('Analyzing: '+filename1)
image = cv2.imread(filename1)

if masks.size:
    logger.debug ('creating masked image...')
    filter_mask = np.zeros(image.shape, dtype=np.uint8)
    cv2.fillPoly(filter_mask, pts=masks, color=(255,255,255))
    masked_image = cv2.bitwise_and(image, filter_mask)
    image = masked_image
    logger.debug ('overwriting masked image: '+filename1)
    cv2.imwrite (filename1,image)


image = imutils.resize(image, width=min(int(config['resize']), image.shape[1]))
# detect people in the image
start = datetime.datetime.now()
r,w = hog.detectMultiScale(image, winStride=winStride, padding=padding, scale=float(config['scale']), useMeanshiftGrouping=meanShift)

if len(r) > 0:
    print ('detected: person')
    logger.debug ('detected person')
elif filename2:
     logger.debug ('person detect failed for '+filename1+' trying '+filename2)
     image = cv2.imread(filename2)
     if masks.size:
            logger.debug ('creating masked image...')
            filter_mask = np.zeros(image.shape, dtype=np.uint8)
            cv2.fillPoly(filter_mask, pts=masks, color=(255,255,255))
            masked_image = cv2.bitwise_and(image, filter_mask)
            image = masked_image
            logger.debug ('overwriting masked image: '+filename1)
            cv2.imwrite (filename2,image)

     image = imutils.resize(image, width=min(int(config['resize']), image.shape[1]))
     # detect people in the image
     r,w = hog.detectMultiScale(image, winStride=winStride,
	 padding=padding, scale=float(config['scale']), useMeanshiftGrouping=meanShift)
     if len(r) > 0:
        print ('detected: person')
        logger.debug ('detected person')
     else:
        logger.debug ('no person detected')

if (args['time']):
    logger.debug('detection took: {}s'.format((datetime.datetime.now() - start).total_seconds()))

if config['delete_after_analyze']=='yes':
    os.remove(filename1)
    if filename2:
        os.remove(filename2)

