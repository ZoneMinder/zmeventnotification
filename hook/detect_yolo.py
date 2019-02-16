#!/usr/bin/python

# version 3.0

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
from shapely.geometry import Polygon
import zmes_hook_helpers.log as log
import zmes_hook_helpers.utils as utils
import zmes_hook_helpers.common_params as g

# once all bounding boxes are detected, we check to see if any of them
# intersect the polygons, if specified
# it also makes sure only patterns specified in detect_pattern are drawn

def processIntersection(bbox, label, conf, match):
    new_label = []
    new_bbox = []
    new_conf = []

    for idx, b in enumerate(bbox):
        doesIntersect = False
        # cv2 rectangle only needs top left and bottom right
        # but to check for polygon intersection, we need all 4 corners
        # b has [a,b,c,d] -> convert to [a,b, c,b, c,d, a,d]
        # https://stackoverflow.com/a/23286299/1361529
        old_b = b
        it = iter(b)
        b = list(zip(it, it))
        b.insert(1, (b[1][0], b[0][1]))
        b.insert(3, (b[0][0], b[1][1]))
        obj = Polygon(b)

        for p in g.polygons:
            poly = Polygon(p['value'])
            if obj.intersects(poly):
                if label[idx] in match:
                    g.logger.debug('{} intersects object:{}[{}]'.format(p['name'], label[idx], b))
                    new_label.append(label[idx])
                    new_bbox.append(old_b)
                    new_conf.append(conf[idx])
                else:
                    g.logger.debug('{} intersects object:{}[{}] but does NOT match your detect_pattern filter'
                                   .format(p['name'], label[idx], b))
                doesIntersect = True
                break

            else:  # of poly intersects
                g.logger.debug('object:{} at {} does not fall into any polygons, removing...'
                               .format(label[idx], obj))
    return new_bbox, new_label, new_conf


# The actual CNN object detection code
# opencv DNN code credit: https://github.com/arunponnusamy/cvlib
initialize = True
net = None
classes = None


def draw_bbox(img, bbox, labels, confidence, colors=None, write_conf=False):

    COLORS = np.random.uniform(0, 255, size=(80, 3))
    polycolor = g.config['poly_color']
    global classes

    # first draw the polygons, if any
    g.logger.debug ("POLYGONS TO DRAW {}".format(g.polygons))
    for ps in g.polygons:
        cv2.polylines(img, [np.asarray(ps['value'])], True, polycolor, thickness=2)

    # now draw object boundaries
    if classes is None:
        classes = populate_class_labels()

    for i, label in enumerate(labels):
        if colors is None:
            color = COLORS[classes.index(label)]
        else:
            color = colors[classes.index(label)]

        if write_conf:
            label += ' ' + str(format(confidence[i] * 100, '.2f')) + '%'
        cv2.rectangle(img, (bbox[i][0], bbox[i][1]), (bbox[i][2], bbox[i][3]), color, 2)
        cv2.putText(img, label, (bbox[i][0], bbox[i][1] - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 2)
    return img


def populate_class_labels():
    class_file_abs_path = g.config['labels']
    f = open(class_file_abs_path, 'r')
    classes = [line.strip() for line in f.readlines()]
    return classes


def get_output_layers(net):
    layer_names = net.getLayerNames()
    output_layers = [layer_names[i[0] - 1] for i in net.getUnconnectedOutLayers()]
    return output_layers


def detect_common_objects(image):
    Height, Width = image.shape[:2]
    scale = 0.00392
    global classes
    config_file_abs_path = g.config['config']
    weights_file_abs_path = g.config['weights']
    global initialize
    global net

    if initialize:
        classes = populate_class_labels()
        net = cv2.dnn.readNet(weights_file_abs_path, config_file_abs_path)
        initialize = False

    blob = cv2.dnn.blobFromImage(image, scale, (416, 416), (0, 0, 0), True, crop=False)
    net.setInput(blob)
    outs = net.forward(get_output_layers(net))

    class_ids = []
    confidences = []
    boxes = []
    conf_threshold = 0.5
    nms_threshold = 0.4

    for out in outs:
        for detection in out:
            scores = detection[5:]
            class_id = np.argmax(scores)
            confidence = scores[class_id]
            if confidence > 0.5:
                center_x = int(detection[0] * Width)
                center_y = int(detection[1] * Height)
                w = int(detection[2] * Width)
                h = int(detection[3] * Height)
                x = center_x - w / 2
                y = center_y - h / 2
                class_ids.append(class_id)
                confidences.append(float(confidence))
                boxes.append([x, y, w, h])

    indices = cv2.dnn.NMSBoxes(boxes, confidences, conf_threshold, nms_threshold)

    bbox = []
    label = []
    conf = []

    for i in indices:
        i = i[0]
        box = boxes[i]
        x = box[0]
        y = box[1]
        w = box[2]
        h = box[3]
        bbox.append([int(round(x)), int(round(y)), int(round(x + w)), int(round(y + h))])
        label.append(str(classes[class_ids[i]]))
        conf.append(confidences[i])

    return bbox, label, conf

# main handler

# set up logging to syslog
log.init('detect_yolo')

# construct the argument parse and parse the arguments
ap = argparse.ArgumentParser()
ap.add_argument('-c', '--config', required=True, help='config file with path')
ap.add_argument('-e', '--eventid', required=True, help='event ID to retrieve')
ap.add_argument('-p', '--eventpath', help='path to store object image file', default='')
ap.add_argument('-m', '--monitorid', help='monitor id - needed for mask')
ap.add_argument('-t', '--time', help='log time')

args, u = ap.parse_known_args()
args = vars(args)
g.polygons = []

# process config file
g.ctx = ssl.create_default_context()
utils.process_config(args,g.ctx)
# now download image(s)
filename1, filename2 = utils.download_files(args)
# filename1 will be the first frame to analyze (typically alarm)
# filename2 will be the second frame to analyze only if the first fails (typically snapshot)

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
bbox, label, conf = detect_common_objects(image)

# Now look for matched patterns in bounding boxes
r = re.compile(g.config['detect_pattern'])
match = list(filter(r.match, label))

bbox, label, conf = processIntersection(bbox, label, conf, match)
g.logger.debug('labels found: {}'.format(label))

if g.config['write_bounding_boxes'] == 'yes' and bbox:
    out = draw_bbox(image, bbox, label, conf, None, False)
    g.logger.debug('Writing out bounding boxes...')
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
    bbox, label, conf = detect_common_objects(image)
    bbox, label, conf = processIntersection(bbox, label, conf, match)
    g.logger.debug('labels found: {}'.format(label))
    if g.config['write_bounding_boxes'] == 'yes' and bbox:
        out = draw_bbox(image, bbox, label, conf, None, False)
        g.logger.debug('Writing out bounding boxes...')
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
