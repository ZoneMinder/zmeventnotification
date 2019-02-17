#!/usr/bin/python

# version: 3.1

# Please don't ask me questions about this script
# its a simple OpenCV person detection script I've proved as a sample 'hook' you can add to the notification server

# credit: https://www.pyimagesearch.com/2015/11/16/hog-detectmultiscale-parameters-explained/

# import the necessary packages
from __future__ import print_function
from imutils.object_detection import non_max_suppression
from imutils import paths
import numpy as np
import imutils
import cv2
import datetime
import os
import re
import sys
import ssl
import argparse

import zmes_hook_helpers.log as log
import zmes_hook_helpers.utils as utils
import zmes_hook_helpers.image_manip as img
import zmes_hook_helpers.common_params as g

# main handler
# set up logging to syslog
log.init('detect_hog')


# construct the argument parse and parse the arguments
ap = argparse.ArgumentParser()
ap.add_argument('-c', '--config', required=True, help='config file with path')
ap.add_argument('-e', '--eventid', required=True,  help='event ID to retrieve')
ap.add_argument('-m', '--monitorid',  help='monitor id - needed for mask')
ap.add_argument('-t', '--time',  help='log time')

args,u = ap.parse_known_args()
args = vars(args)

# process config file
g.ctx = ssl.create_default_context()
utils.process_config(args,g.ctx)
# now download image(s)
filename1, filename2 = utils.download_files(args)


winStride = g.config['stride']
padding = g.config['padding']
meanShift = True if int(g.config['mean_shift']) > 0 else False

# initialize the HOG descriptor/person detector
hog = cv2.HOGDescriptor()
hog.setSVMDetector(cv2.HOGDescriptor_getDefaultPeopleDetector())

g.logger.info ('Analyzing: '+filename1)
image = cv2.imread(filename1)


# Unlike in Yolo, we can't do polygon intersection
# as there are no bounding boxes. So we mask out image

if g.polygons:
    filter_mask = np.zeros(image.shape, dtype=np.uint8)
    for p in g.polygons:
        g.logger.debug ('creating mask of {}'.format(p))
        r = [np.asarray(p['value'])]
        cv2.fillPoly(filter_mask, pts=r, color=(255,255,255))
    masked_image = cv2.bitwise_and(image, filter_mask)
    image = masked_image
    g.logger.debug ('overwriting masked image: '+filename1)
    cv2.imwrite (filename1,image)


image = imutils.resize(image, width=min(int(g.config['resize']), image.shape[1]))
# detect people in the image
start = datetime.datetime.now()
r,w = hog.detectMultiScale(image, winStride=winStride, padding=padding, scale=float(g.config['scale']), useMeanshiftGrouping=meanShift)

if len(r) > 0:
    print ('detected: person')
    g.logger.debug ('detected person')
elif filename2:
     g.logger.debug ('person detect failed for '+filename1+' trying '+filename2)
     image = cv2.imread(filename2)
     if g.polygons:
        filter_mask = np.zeros(image.shape, dtype=np.uint8)
        for p in g.polygons:
            g.logger.debug ('creating mask of {}'.format(p))
            r = [np.asarray(p['value'])]
            cv2.fillPoly(filter_mask, pts=r, color=(255,255,255))
        masked_image = cv2.bitwise_and(image, filter_mask)
        image = masked_image
        g.logger.debug ('overwriting masked image: '+filename1)
        cv2.imwrite (filename1,image)
     
     image = imutils.resize(image, width=min(int(config['resize']), image.shape[1]))
     # detect people in the image
     r,w = hog.detectMultiScale(image, winStride=winStride,
	 padding=padding, scale=float(config['scale']), useMeanshiftGrouping=meanShift)
     if len(r) > 0:
        print ('detected: person')
        g.logger.debug ('detected person')
     else:
        g.logger.debug ('no person detected')

if (args['time']):
    g.logger.debug('detection took: {}s'.format((datetime.datetime.now() - start).total_seconds()))

if g.config['delete_after_analyze']=='yes':
    os.remove(filename1)
    if filename2:
        os.remove(filename2)

