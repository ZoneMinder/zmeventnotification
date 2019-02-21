#!/usr/bin/python

# version: 3.1

# Please don't ask me questions about this script
# its a simple OpenCV person detection script I've proved as a sample 'hook' you can add to the notification server

# credit: https://www.pyimagesearch.com/2015/11/16/hog-detectmultiscale-parameters-explained/

# import the necessary packages
from __future__ import division
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


h, w = image.shape[:2]
if not g.polygons:
    g.polygons.append({'name': 'full_image', 'value': [(0, 0), (w, 0), (w, h), (0, h)]})
    g.logger.debug('No polygon area specfied, so adding a full image polygon:{}'.format(g.polygons))


if g.config['resize']:
    g.logger.debug('resizing to {} before analysis...'.format(g.config['resize']))
    image = imutils.resize(image, width=min(int(g.config['resize']), image.shape[1]))
    newh, neww = image.shape[:2]
    utils.rescale_polygons(neww / w, newh / h)

# detect people in the image
start = datetime.datetime.now()
r,w = hog.detectMultiScale(image, winStride=winStride, padding=padding, scale=float(g.config['scale']), useMeanshiftGrouping=meanShift)
labels = []
classes=[]
conf=[]

# make it yolo format for utility functions
for i in r:
    labels.append('person')
    classes.append('person')
    conf.append('1')


r, labels, conf = img.processIntersection(r, labels, conf, ['person'])

# draw the original bounding boxes
if g.config['write_bounding_boxes'] == 'yes':
    g.logger.debug ('writing bounding boxes')
    img.draw_bbox(image,r,labels, classes, conf, None, False)
    cv2.imwrite (filename1,image)

if len(r) > 0:
    print ('detected: person')
    g.logger.debug ('detected person')
elif filename2:
     g.logger.debug ('person detect failed for '+filename1+' trying '+filename2)
     image = cv2.imread(filename2)
     image = imutils.resize(image, width=min(int(g.config['resize']), image.shape[1]))
     # detect people in the image
     r,w = hog.detectMultiScale(image, winStride=winStride,
	 padding=padding, scale=float(g.config['scale']), useMeanshiftGrouping=meanShift)
     labels = []
     classes=[]
     conf=[]

     # make it yolo format for utility functions
     for i in r:
        labels.append('person')
        classes.append('person')
        conf.append('1')
     r, labels, conf = img.processIntersection(r, labels, conf, ['person'])
     # draw the original bounding boxes
     if g.config['write_bounding_boxes'] == 'yes':
        g.logger.debug ('writing bounding boxes')
        img.draw_bbox(image,r,labels, classes,conf, None, False)
        cv2.imwrite (filename2,image)

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

