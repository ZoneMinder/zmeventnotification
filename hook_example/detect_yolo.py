#!/usr/bin/python

# version 2.1

# Alternate detection script using neural nets and YoloV3. 
# slower than openCV HOG but much more accurate
# also capable of detecting many more objects

# Needs opencv-python-3.4.3.18 or above
# On my non GPU machine, this takes 2 seconds while HOG takes 0.2 seconds

# This trained model is able to detect the following 80 categories
# https://github.com/pjreddie/darknet/blob/master/data/coco.names

# opencv DNN code credit: https://github.com/arunponnusamy/cvlib

import sys
import cv2
import argparse
import datetime
import os
import numpy as np
import re
import configparser
import urllib
import imutils

def str2arr(str):
    return  [map(int,x.strip().split(',')) for x in str.split(' ')]

# The actual CNN object detection code
initialize = True
net = None
classes = None

def populate_class_labels():
    class_file_abs_path = config['labels']
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
    config_file_abs_path = config['config']
    weights_file_abs_path = config['weights']
    global initialize
    global net

    if initialize:
        classes = populate_class_labels()
        net = cv2.dnn.readNet(weights_file_abs_path, config_file_abs_path)
        initialize = False

    blob = cv2.dnn.blobFromImage(image, scale, (416,416), (0,0,0), True, crop=False)
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
        bbox.append([round(x), round(y), round(x+w), round(y+h)])
        label.append(str(classes[class_ids[i]]))
        conf.append(confidences[i])
        
    return bbox, label, conf

# main handler

# set up logging to syslog
import logging
import logging.handlers
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
handler = logging.handlers.SysLogHandler('/dev/log')
formatter = logging.Formatter('detect_yolo:[%(process)d]: %(levelname)s [%(message)s]')
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
    config['detect_pattern']=config_file['general'].get('detect_pattern','.*');
    config['frame_id']=config_file['general'].get('frame_id','snapshot');
    config['resize']=config_file['general'].get('resize','800');
    config['delete_after_analyze']=config_file['general'].get('delete_after_analyze','no');
    config['show_percent']=config_file['general'].get('show_percent','no');
    config['log_level']=config_file['general'].get('log_level','info');

    config['config']=config_file['yolo'].get('yolo','/var/detect/models/yolov3/yolov3.cfg');
    config['weights']=config_file['yolo'].get('yolo','/var/detect/models/yolov3/yolov3.weights');
    config['labels']=config_file['yolo'].get('yolo','/var/detect/models/yolov3/yolov3_classes.txt');

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


# filename1 will be the first frame to analyze (typically alarm)
# filename2 will be the second frame to analyze only if the first fails (typically snapshot)
prefix = '[x] ' # not best match

if config['frame_id']=='bestmatch':
    prefix = '[a] '

image = cv2.imread(filename1)

# If a mask is specified, create a black and white mask and apply it on image
if masks.size:
    logger.debug ('creating masked image...')
    filter_mask = np.zeros(image.shape, dtype=np.uint8)
    cv2.fillPoly(filter_mask, pts=masks, color=(255,255,255))
    masked_image = cv2.bitwise_and(image, filter_mask)
    image = masked_image
    logger.debug ('overwriting masked image: '+filename1)
    cv2.imwrite (filename1,image)

logger.info ('Analyzing image '+filename1+' with pattern: ' + config['detect_pattern'])
start = datetime.datetime.now()
logger.debug ('resizing to '+config['resize']+' before analysis...')
image = imutils.resize(image, width=min(int(config['resize']), image.shape[1]))
bbox, label, conf = detect_common_objects(image)
r = re.compile(config['detect_pattern'])
match = list(filter(r.match, label))
if len (match) == 0 and filename2:
        # switch to next image
        logger.info ('pattern match failed for '+filename1+' trying '+filename2)
        prefix = '[s] '
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

        bbox, label, conf = detect_common_objects(image)
        match = list(filter(r.match, label))
        if len (match) == 0:
            label = []
            conf = []

if (args['time']):
    logger.debug('detection took: {}s'.format((datetime.datetime.now() - start).total_seconds()))

pred=''

seen = {}
for l,c in zip (label,conf):
    if l not in seen:
        if config['show_percent'] == 'no':
            pred = pred +l+' '
        else:
            pred = pred +l+':{:.0%}'.format(c)+' '
        seen[l] = 1

if pred !='':
    pred = prefix+'detected:'+pred
    logger.debug ('Prediction string:'+pred)
print (pred)
if config['delete_after_analyze']=='yes':
    os.remove(filename1)
    if filename2: 
        os.remove(filename2) 

