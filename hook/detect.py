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
    filename_alarm, filename_snapshot = utils.download_files(args)
    # filename_alarm will be the first frame to analyze (typically alarm)
    # filename_snapshot will be the second frame to analyze only if the first fails (typically snapshot)
else:
    g.logger.debug('TESTING ONLY: reading image from {}'.format(args['file']))
    filename_alarm = args['file']
    filename_snapshot = ''

if g.config['frame_id'] == 'bestmatch':
    prefix = '[a] '  # we will first analyze alarm
else:
    prefix = '[x] '

for filename in [filename_alarm, filename_snapshot]:
    if not filename:
        continue
    if filename == filename_snapshot:
    # if we are processing filename_snapshot, we are using bestmatch
        prefix = '[s] '

    
    image = cv2.imread(filename)
    oldh, oldw = image.shape[:2]

    g.logger.info ('About to anayze file: {}'.format(filename))
    if not g.polygons:
        g.polygons.append({'name': 'full_image', 'value': [(0, 0), (oldw, 0), (oldw, oldh), (0, oldh)]})
        g.logger.debug('No polygon area specfied, so adding a full image polygon:{}'.format(g.polygons))

    start = datetime.datetime.now()
    # we resize polys only one time
    if g.config['resize'] and filename == filename_alarm:
        g.logger.debug('resizing to {} before analysis...'.format(g.config['resize']))
        image = imutils.resize(image, width=min(int(g.config['resize']), image.shape[1]))
        newh, neww = image.shape[:2]
        utils.rescale_polygons(neww / oldw, newh / oldh)

    g.logger.info('Analyzing image with pattern: {}'.format( g.config['detect_pattern']))
    # detect objects
    bbox = []
    label = []
    conf = []
    classes = []
    for model in g.config['models']:
        g.logger.debug ('Using model: {}'.format(model))
        if model == 'yolo':
            m = yolo.Yolo()
        elif model == 'hog':
            m = hog.Hog()
        elif model == 'face':
            m = face.Face()
        else:
            g.logger.error('Invalid model {}'.format(model))
            exit(0)


        b, l, c = m.detect(image)

        # Now look for matched patterns in bounding boxes
        r = re.compile(g.config['detect_pattern'])
        match = list(filter(r.match, l))
        if model == 'face':
            g.logger.debug ('Appending known faces to filter list')
            for cls in m.get_classes():
                if not cls in match:
                    print ('Adding {}'.format(cls))
                    match=match+[cls]

        # now filter these with polygon areas
        b, l, c = img.processIntersection(b, l, c, match)
        if b:
            bbox.append(b)
            label.append(l)
            conf.append(c)
            classes.append(m.get_classes())
            g.logger.debug('labels found: {}'.format(l))
        else:
            g.logger.debug ('No matches found using model:{}'.format(model))

    # At this stage, all models are run on this file
    
    if len(bbox) == 0:
        g.logger.debug ('No patterns found using any models in {}'.format(filename))
    else:
        # we have matches, draw and quit loop
        if g.config['write_bounding_boxes'] == 'yes':
            for idx, b in enumerate (bbox):
                out = img.draw_bbox(image, b, label[idx], classes[idx], conf[idx], None, False)
                # for the next iteration, use the generated image
                image = out
            
                g.logger.debug('Writing out bounding boxes to {}...'.format(filename))
            cv2.imwrite(filename, image)
            if (args['eventpath']):
                g.logger.debug('Writing detected image to {}'.format(args['eventpath']))
                cv2.imwrite(args['eventpath'] + '/objdetect.jpg', image)
        break;

if (args['time']):
    g.logger.debug('detection took: {}s'.format((datetime.datetime.now() - start).total_seconds()))

# Now create prediction string

pred = ''
for idx,la in enumerate (label):
    seen = {}
    for l, c in zip(la, conf[idx]):
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
    if filename_alarm:
        os.remove(filename_alarm)
    if filename_snapshot:
        os.remove(filename_snapshot)
