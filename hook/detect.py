#!/usr/bin/python

# version 3.1

# Alternate detection script using neural nets and YoloV3.
# slower than openCV HOG but much more accurate
# also capable of detecting many more objects

# Needs opencv-python-3.4.3.18 or above
# On my non GPU machine, this takes 2 seconds while HOG takes 0.2 seconds

# This trained model is able to detect the following 80 categories
# https://github.com/pjreddie/darknet/blob/master/data/coco.names

from __future__ import division
import sys
import cv2
import argparse
import datetime
import os
import numpy as np
import re
import imutils
import ssl
import zmes_hook_helpers.log as log
import zmes_hook_helpers.utils as utils
import zmes_hook_helpers.image_manip as img
import zmes_hook_helpers.common_params as g

import  zmes_hook_helpers.yolo as yolo
import  zmes_hook_helpers.hog as hog
import  zmes_hook_helpers.face as face

# main handler

# set up logging to syslog
log.init('detect')

# construct the argument parse and parse the arguments
ap = argparse.ArgumentParser()
ap.add_argument('-c', '--config', required=True, help='config file with path')
ap.add_argument('-e', '--eventid', required=True, help='event ID to retrieve')
ap.add_argument('-p', '--eventpath', help='path to store object image file', default='')
ap.add_argument('-m', '--monitorid', help='monitor id - needed for mask')
ap.add_argument('-t', '--time', help='log time')

ap.add_argument('-f', '--file', help='internal testing use only - skips event download')

args, u = ap.parse_known_args()
args = vars(args)
g.polygons = []

# process config file
g.ctx = ssl.create_default_context()
utils.process_config(args,g.ctx)
# now download image(s)

if not args['file']:
    filename1, filename2 = utils.download_files(args)
    # filename1 will be the first frame to analyze (typically alarm)
    # filename2 will be the second frame to analyze only if the first fails (typically snapshot)
else:
    g.logger.debug('TESTING ONLY: reading image from {}'.format(args['file']))
    filename1 = args['file']
    filename2 = ''

if g.config['frame_id'] == 'bestmatch':
    prefix = '[a] '  # we will first analyze alarm
else:
    prefix = '[x] '

image = cv2.imread(filename1)
oldh, oldw = image.shape[:2]

if not g.polygons:
    g.polygons.append({'name': 'full_image', 'value': [(0, 0), (oldw, 0), (oldw, oldh), (0, oldh)]})
    g.logger.debug('No polygon area specfied, so adding a full image polygon:{}'.format(g.polygons))

g.logger.info('Analyzing image {} with pattern: {}'.format(filename1, g.config['detect_pattern']))
start = datetime.datetime.now()
if g.config['resize']:
    g.logger.debug('resizing to {} before analysis...'.format(g.config['resize']))
    image = imutils.resize(image, width=min(int(g.config['resize']), image.shape[1]))
    newh, neww = image.shape[:2]
    utils.rescale_polygons(neww / oldw, newh / oldh)

# detect objects
#y = yolo.Yolo()
y =  face.Face()
#y = hog.Hog()
bbox, label, conf = y.detect(image)

# Now look for matched patterns in bounding boxes
r = re.compile(g.config['detect_pattern'])
match = list(filter(r.match, label))

bbox, label, conf = img.processIntersection(bbox, label, conf, match)
g.logger.debug('labels found: {}'.format(label))

if g.config['write_bounding_boxes'] == 'yes' and bbox:
    out = img.draw_bbox(image, bbox, label, y.get_classes(), conf, None, False)
    g.logger.debug('Writing out bounding boxes to {}...'.format(filename1))
    cv2.imwrite(filename1, out)
    if (args['eventpath']):
        g.logger.debug('Writing detected image to {}'.format(args['eventpath']))
        cv2.imwrite(args['eventpath'] + '/objdetect.jpg', out)

# if bbox has 0 elements, nothing matched
if len(bbox) == 0 and filename2:
    # switch to next image
    g.logger.debug('pattern match failed for {}, trying {}'.format(filename1, filename2))
    prefix = '[s] '  # snapshot analysis
    image = cv2.imread(filename2)
    if g.config['resize']:
        g.logger.debug('resizing to {} before analysis...'.format(g.config['resize']))
        image = imutils.resize(image, width=min(int(g.config['resize']), image.shape[1]))
    bbox, label, conf = y.detect(image)
    match = list(filter(r.match, label))
    bbox, label, conf = img.processIntersection(bbox, label, conf, match)
    g.logger.debug('labels found: {}'.format(label))
    if g.config['write_bounding_boxes'] == 'yes' and bbox:
        out = img.draw_bbox(image, bbox, label, y.get_classes(), conf, None, False)
        g.logger.debug('Writing out bounding boxes to {}...'.format(filename2))
        cv2.imwrite(filename2, out)
        if (args['eventpath']):
            g.logger.debug('Writing detected image to {}'.format(args['eventpath']))
            cv2.imwrite(args['eventpath'] + '/objdetect.jpg', out)
    if len(bbox) == 0:
        g.logger.debug('pattern match failed for {} as well'.format(filename2))
        label = []
        conf = []

if (args['time']):
    g.logger.debug('detection took: {}s'.format((datetime.datetime.now() - start).total_seconds()))

pred = ''

seen = {}
for l, c in zip(label, conf):
    if l not in seen:
        if g.config['show_percent'] == 'no':
            pred = pred + l + ','
        else:
            pred = pred + l + ':{:.0%}'.format(c) + ' '
        seen[l] = 1

if pred != '':
    pred = pred.rstrip(',')
    pred = prefix + 'detected:' + pred
    g.logger.debug('Prediction string:{}'.format(pred))
print (pred)
if g.config['delete_after_analyze'] == 'yes':
    if filename1:
        os.remove(filename1)
    if filename2:
        os.remove(filename2)
