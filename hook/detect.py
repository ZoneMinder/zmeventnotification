#!/usr/bin/python2

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


def append_suffix(filename,token):
    f,e = os.path.splitext(filename)
    return f+token+e

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
    filename_alarm, filename_snapshot, filename_alarm_bbox, filename_snapshot_bbox = utils.download_files(args)
    # filename_alarm will be the first frame to analyze (typically alarm)
    # filename_snapshot will be the second frame to analyze only if the first fails (typically snapshot)
else:
    g.logger.debug('TESTING ONLY: reading image from {}'.format(args['file']))
    filename_alarm = args['file']
    filename_alarm_bbox = append_suffix(filename_alarm, '-bbox')
    filename_snapshot = ''
    filename_snapshot_bbox = ''

if g.config['frame_id'] == 'bestmatch':
    prefix = '[a] '  # we will first analyze alarm
else:
    prefix = '[x] '

start = datetime.datetime.now()
# First do detection for alarmed image then snapshot
poly_scaled = False
for filename in [filename_alarm, filename_snapshot]:
    if not filename:
        continue
    if filename == filename_snapshot:
    # if we are processing filename_snapshot, we are using bestmatch
        prefix = '[s] '
        bbox_f = filename_snapshot_bbox
    else:
        bbox_f = filename_alarm_bbox
    
    image = cv2.imread(filename)
    if image is None:
        g.logger.error ('Error reading {}. It either does not exist or is invalid'.format(filename))
        raise ValueError('Error reading file {}. It either does not exist or is invalid'.format(filename))
        
    oldh, oldw = image.shape[:2]

    g.logger.info ('About to anayze file: {}'.format(filename))
    if not g.polygons:
        g.polygons.append({'name': 'full_image', 'value': [(0, 0), (oldw, 0), (oldw, oldh), (0, oldh)]})
        g.logger.debug('No polygon area specfied, so adding a full image polygon:{}'.format(g.polygons))

    if g.config['resize']:
        g.logger.debug('resizing to {} before analysis...'.format(g.config['resize']))
        image = imutils.resize(image, width=min(int(g.config['resize']), image.shape[1]))
        newh, neww = image.shape[:2]
        # we resize polys only one time
        # when we get to the next image (snapshot), polygons have already resized
        if not poly_scaled:
           utils.rescale_polygons(neww / oldw, newh / oldh)
           poly_scaled = True

    g.logger.info('Analyzing image with pattern: {}'.format( g.config['detect_pattern']))
    # detect objects
    bbox = []
    label = []
    conf = []
    classes = []

    # Apply all configured models to each file
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
            raise ValueError('Invalid model {}'.format(model))

        # each detection type has a detect method
        b, l, c = m.detect(image)

        # Now look for matched patterns in bounding boxes
        r = re.compile(g.config['detect_pattern'])
        match = list(filter(r.match, l))
        # If you want face recognition, we need to add the list of found faces
        # to the allowed list or they will be thrown away during the intersection
        # check
        if model == 'face':
            g.logger.debug ('Appending known faces to filter list')
            for cls in m.get_classes():
                if not cls in match:
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
        for idx, b in enumerate (bbox):
            out = img.draw_bbox(image, b, label[idx], classes[idx], conf[idx], None,False)
            image = out
        
        if g.config['write_debug_image'] == 'yes':
            g.logger.debug('Writing out debug bounding box image to {}...'.format(bbox_f))
            cv2.imwrite(bbox_f, image)

        if g.config['write_image_to_zm'] == 'yes':
            if (args['eventpath']):
                g.logger.debug('Writing detected image to {}'.format(args['eventpath']))
                cv2.imwrite(args['eventpath'] + '/objdetect.jpg', image)
            else:
                g.logger.error ('Could not write image to ZoneMinder as eventpath not present')
        # stop analysis if this file worked
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
