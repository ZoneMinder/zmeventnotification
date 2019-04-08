#!/usr/bin/python

# Main detection script that loads different detection models
# look at zmes_hook_helpers for different detectors

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
#import hashlib

import zmes_hook_helpers.log as log
import zmes_hook_helpers.utils as utils
import zmes_hook_helpers.image_manip as img
import zmes_hook_helpers.common_params as g

import zmes_hook_helpers.yolo as yolo
import zmes_hook_helpers.hog as hog
from zmes_hook_helpers.__init__ import __version__


def append_suffix(filename, token):
    f, e = os.path.splitext(filename)
    return f + token + e

    

# main handler

# set up logging to syslog

# construct the argument parse and parse the arguments
ap = argparse.ArgumentParser()
ap.add_argument('-c', '--config', required=True, help='config file with path')
ap.add_argument('-e', '--eventid', required=True, help='event ID to retrieve')
ap.add_argument('-p', '--eventpath', help='path to store object image file', default='')
ap.add_argument('-m', '--monitorid', help='monitor id - needed for mask')
ap.add_argument('-t', '--time', help='log time', action='store_true')
ap.add_argument('-v', '--version', help='print version and quit',action='store_true')

ap.add_argument('-f', '--file', help='internal testing use only - skips event download')

args, u = ap.parse_known_args()
args = vars(args)

if args['monitorid']:
    log.init('detect',args['monitorid'])
else:
    log.init('detect')

g.logger.info ('---------| app version: {} |------------'.format(__version__))
if args['version']:
    print ('---------| app version: {} |------------'.format(__version__))
    exit(0)

g.polygons = []

# process config file
g.ctx = ssl.create_default_context()


utils.process_config(args, g.ctx)
# now download image(s)

if not args['file']:
    filename1, filename2, filename1_bbox, filename2_bbox = utils.download_files(args)
    # filename_alarm will be the first frame to analyze (typically alarm)
    # filename_snapshot will be the second frame to analyze only if the first fails (typically snapshot)
else:
    g.logger.debug('TESTING ONLY: reading image from {}'.format(args['file']))
    filename1 = args['file']
    filename1_bbox = append_suffix(filename1, '-bbox')
    filename2 = ''
    filename2_bbox = ''


start = datetime.datetime.now()

# Read images to analyze
image2 = None
image1 = cv2.imread(filename1)
if image1 is None: # can't have this None, something went wrong
    g.logger.error('Error reading {}. It either does not exist or is invalid'.format(filename1))
    raise ValueError('Error reading file {}. It either does not exist or is invalid'.format(filename1))
oldh, oldw = image1.shape[:2]
if filename2: # may be none
    image2 = cv2.imread(filename2)
    if image2 is None:
        g.logger.error('Error reading {}. It either does not exist or is invalid'.format(filename2))
        raise ValueError('Error reading file {}. It either does not exist or is invalid'.format(filename2))
# create a scaled polygon for object intersection checks
if not g.polygons:
        g.polygons.append({'name': 'full_image', 'value': [(0, 0), (oldw, 0), (oldw, oldh), (0, oldh)]})
        g.logger.debug('No polygon area specfied, so adding a full image polygon:{}'.format(g.polygons))
if g.config['resize']:
    
    g.logger.debug('resizing to {} before analysis...'.format(g.config['resize']))
    image1 = imutils.resize(image1, width=min(int(g.config['resize']), image1.shape[1]))
    if image2 is not None:
        image2 = imutils.resize(image2, width=min(int(g.config['resize']), image2.shape[1]))
    
    newh, neww = image1.shape[:2]
    utils.rescale_polygons(neww / oldw, newh / oldh)

 # Apply all configured models to each file


matched_file = None
bbox = []
label = []
conf = []
classes = []

for model in g.config['models']:
    # instaniate the right model
    # after instantiation run all files with it, 
    # so no need to do 2x instantiations
    
    if model == 'yolo':
        m = yolo.Yolo()
    elif model == 'hog':
        m = hog.Hog()
    elif model == 'face':
        try:
            import zmes_hook_helpers.face as face
        except ImportError:
            g.logger.error ('Error importing face recognition. Make sure you did sudo -H pip install face_recognition')
            raise

        m = face.Face(upsample_times=g.config['face_upsample_times'], 
                        num_jitters=g.config['face_num_jitters'],
                        model=g.config['face_model'])
    else:
        g.logger.error('Invalid model {}'.format(model))
        raise ValueError('Invalid model {}'.format(model))

    # read the detection pattern we need to apply as a filter
    r = re.compile(g.config['detect_pattern'])
    
    # Apply the model to all files
    for filename in [filename1, filename2]:
        if filename is None: 
            continue
        if matched_file and  filename != matched_file:
        # this will only happen if we tried model A, we found a match
        # and then we looped to model B to find more matches (that is, detection_mode is all)
        # in this case, we only want to match more models to the file we found a first match
            g.logger.debug ('Skipping {} as we earlier matched {}'.format(filename, matched_file))
            continue
        g.logger.debug('Using model: {} with {}'.format(model, filename))
        image = image1 if filename==filename1 else image2
        b, l, c = m.detect(image)
        # Now look for matched patterns in bounding boxes
        match = list(filter(r.match, l))
        # If you want face recognition, we need to add the list of found faces
        # to the allowed list or they will be thrown away during the intersection
        # check
        if model == 'face':
            g.logger.debug('Appending known faces to filter list')
            match = match + ['face'] # unknown face
            for cls in m.get_classes():
                if not cls in match:
                    match = match + [cls]

        # now filter these with polygon areas
        b, l, c = img.processIntersection(b, l, c, match)
        if b:
            bbox.append(b)
            label.append(l)
            conf.append(c)
            classes.append(m.get_classes())
            g.logger.debug('labels found: {}'.format(l))
            g.logger.debug ('match found in {}, breaking file loop...'.format(filename))
            matched_file = filename
            break # if we found a match, no need to process the next file
        else:
            g.logger.debug('No match found in {} using model:{}'.format(filename,model))
            found_match = False
        # file loop
    # model loop
    if matched_file and g.config['detection_mode'] == 'first':
        g.logger.debug('detection mode is set to first, breaking out of model loop...')
        break

# all models loops, all files looped

if not matched_file:
        g.logger.debug('No patterns found using any models in all files')

else:
    # we have matches
    if matched_file == filename1:
        image = image1
        bbox_f = filename1_bbox
    else:
        image = image2
        bbox_f = filename2_bbox
  
    for idx, b in enumerate(bbox):
        out = img.draw_bbox(image, b, label[idx], classes[idx], conf[idx], None, False)
        image = out

    if g.config['write_debug_image'] == 'yes':
        g.logger.debug('Writing out debug bounding box image to {}...'.format(bbox_f))
        cv2.imwrite(bbox_f, image)

    if g.config['write_image_to_zm'] == 'yes':
        if (args['eventpath']):
            g.logger.debug('Writing detected image to {}'.format(args['eventpath']))
            cv2.imwrite(args['eventpath'] + '/objdetect.jpg', image)
        else:
            g.logger.error('Could not write image to ZoneMinder as eventpath not present')
    # Now create prediction string

    if g.config['frame_id'] == 'bestmatch':
        if matched_file == filename1:
            prefix = '[a] '  # we will first analyze alarm
        else:
            prefix = '[s]'
    else:
        prefix = '[x] '

    pred = ''
    for idx, la in enumerate(label):
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

    # end of matched_file

if (args['time']):
    g.logger.debug('detection took: {}s'.format((datetime.datetime.now() - start).total_seconds()))


if g.config['delete_after_analyze'] == 'yes':
    if filename1:
        os.remove(filename_alarm)
    if filename2:
        os.remove(filename_snapshot)
