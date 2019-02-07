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
import configparser
import urllib
import imutils
import logging
import logging.handlers
import ssl
from shapely.geometry import Polygon

# converts a string of cordinates 'x1,y1 x2,y2 ...' to a tuple set. We use this
# to parse the polygon parameters in the ini file
def str2tuple(str):
    return  [tuple(map(int,x.strip().split(','))) for x in str.split(' ')]

# re-scales the polygons you specified in the config file
# to the size we use for analysis (by default min(image width,800))
def adjustPolygons(xfactor, yfactor,polygons):
    newps = []
    for p in polygons:
        newp = []
        for x,y in p['value']:
            newx = int(x * xfactor)
            newy = int (y * yfactor)
            newp.append((newx,newy))
        newps.append({'name':p['name'], 'value':newp})
    logger.debug('resized polygons x={}/y={}: {}'.format(xfactor,yfactor,newps))
    return newps

# once all bounding boxes are detected, we check to see if any of them
# intersect the polygons, if specified
def checkIntersection(labels, polygons, bbox):
    for idx,b in enumerate(bbox):
        doesIntersect = False

        # cv2 rectangle only needs top left and bottom right
        # but to check for polygon intersection, we need all 4 corners
        # b has [a,b,c,d] -> convert to [a,b, c,b, c,d, a,d]
        # https://stackoverflow.com/a/23286299/1361529
        it = iter(b)
        b = zip(it,it)
        b.insert (1, (b[1][0], b[0][1]))
        b.insert (3, (b[0][0], b[1][1]))
        obj = Polygon(b)

        for p in polygons:
            poly = Polygon(p['value'])
            if poly.intersects(obj):
                logger.debug( '{} intersects object:{}[{}]'.format(p['name'],labels[idx],b))
                doesIntersect = True
                break
            if doesIntersect == False:
                logger.debug ( 'object:{} at [{}] does not fall into any polygons, removing...'.format(labels[idx],obj))
                labels.pop(idx)
                bbox.pop(idx)

# The actual CNN object detection code
# opencv DNN code credit: https://github.com/arunponnusamy/cvlib
initialize = True
net = None
classes = None

def draw_bbox(img, bbox, labels, confidence, colors=None, write_conf=False, polys=[]):

    COLORS = np.random.uniform(0, 255, size=(80, 3))
    polycolor = (127, 140, 141)
    global classes

    # first draw the polygons, if any
    for ps in polys:
            cv2.polylines(img, [np.asarray(ps['value'])],True,polycolor,thickness=2 )

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
        cv2.rectangle(img, (bbox[i][0],bbox[i][1]), (bbox[i][2],bbox[i][3]), color, 2)
        cv2.putText(img, label, (bbox[i][0],bbox[i][1]-10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 2)
    return img


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
        bbox.append([int(round(x)), int(round(y)), int(round(x+w)), int(round(y+h))])
        label.append(str(classes[class_ids[i]]))
        conf.append(confidences[i])
        
    return bbox, label, conf

# main handler

# set up logging to syslog
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
ap.add_argument('-m', '--monitorid',  help='monitor id - needed for mask')
ap.add_argument('-t', '--time',  help='log time')

args,u = ap.parse_known_args()
args = vars(args)

# process config file
config_file = configparser.ConfigParser()
config_file.read(args['config'])
ctx = ssl.create_default_context()

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
    config['allow_self_signed']=config_file['general'].get('allow_self_signed','yes');

    config['config']=config_file['yolo'].get('yolo','/var/detect/models/yolov3/yolov3.cfg');
    config['weights']=config_file['yolo'].get('yolo','/var/detect/models/yolov3/yolov3.weights');
    config['labels']=config_file['yolo'].get('yolo','/var/detect/models/yolov3/yolov3_classes.txt');
    config['write_bounding_boxes']=config_file['yolo'].get('write_bounding_boxes','yes');

    if config['log_level']=='debug':
        logger.setLevel(logging.DEBUG)
    elif config['log_level']=='info':
        logger.setLevel(logging.INFO)
    elif config['log_level']=='error':
        logger.setLevel(logging.ERROR)

    if config['allow_self_signed'] == 'yes':
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        logger.debug('allowing self-signed certs to work...')
    else:
        logger.debug ('strict SSL cert checking is on...')


    # get the polygons, if any, for the supplied monitor
    polygons=[]
    if args['monitorid']:
            if config_file.has_section('object-areas-'+args['monitorid']):
                itms = config_file['object-areas-'+args['monitorid']].items()
                if itms: 
                    logger.debug ('object areas definition found for monitor:{}'.format(args['monitorid']))
                else:
                    logger.debug ('object areas section found, but no polygon entries found')
                for k,v in itms:
                    polygons.append({'name':k, 'value':str2tuple(v)})
                    logger.debug ('adding polygon: {} [{}]'.format(k,v))
            else:
                logger.debug ('no object areas found for monitor:{}'.format(args['monitorid']))
    else:
        logger.info ('Ignoring object areas, as you did not provide a monitor id')  
        
except Exception,e:
    logger.error('Error parsing config:{}'.format(args['config']))
    logger.error('Error was:{}'.format(e))
    exit(0)


# now download image(s)
if config['frame_id'] == 'bestmatch':
    # download both alarm and snapshot
    filename1 = config['image_path']+'/'+args['eventid']+'-alarm.jpg'
    filename2 = config['image_path']+'/'+args['eventid']+'-snapshot.jpg'
    url = config['portal']+'/index.php?view=image&eid='+args['eventid']+'&fid=alarm'+ \
          '&username='+config['user']+'&password='+config['password']
    urllib.urlretrieve(url,filename1,context=ctx)

    url = config['portal']+'/index.php?view=image&eid='+args['eventid']+'&fid=snapshot'+ \
          '&username='+config['user']+'&password='+config['password']
    urllib.urlretrieve(url,filename2,context=ctx)
else:
    # only download one
    filename1 = config['image_path']+'/'+args['eventid']+'.jpg'
    filename2 = ''
    url = config['portal']+'/index.php?view=image&eid='+args['eventid']+'&fid='+config['frame_id']+ \
          '&username='+config['user']+'&password='+config['password']
    urllib.urlretrieve(url,filename1, context=ctx)


# filename1 will be the first frame to analyze (typically alarm)
# filename2 will be the second frame to analyze only if the first fails (typically snapshot)

if config['frame_id']=='bestmatch':
    prefix = '[a] ' # we will first analyze alarm
else:
    prefix = '[x] '

image = cv2.imread(filename1)
oldh, oldw = image.shape[:2]

logger.info ('Analyzing image {} with pattern: {}'.format(filename1, config['detect_pattern']))
start = datetime.datetime.now()
if config['resize']:
    logger.debug ('resizing to {} before analysis...'.format(config['resize']))
    image = imutils.resize(image, width=min(int(config['resize']), image.shape[1]))
    newh, neww = image.shape[:2]
    polygons = adjustPolygons(neww/oldw, newh/oldh, polygons)

# detect objects
bbox, label, conf = detect_common_objects(image)
checkIntersection(label, polygons, bbox)

if config['write_bounding_boxes']=='yes' and bbox:
    out = draw_bbox(image, bbox, label, conf, None, False, polygons)
    logger.debug ('Writing out bounding boxes...')
    cv2.imwrite(filename1, out)

r = re.compile(config['detect_pattern'])
match = list(filter(r.match, label))
if len (match) == 0 and filename2:
        # switch to next image
        logger.debug ('pattern match failed for {}, trying {}'.format(filename1,filename2))
        prefix = '[s] ' # snapshot analysis
        image = cv2.imread(filename2)
        if config['resize']:
            logger.debug ('resizing to {} before analysis...'.format(config['resize']))
            image = imutils.resize(image, width=min(int(config['resize']), image.shape[1]))
        bbox, label, conf = detect_common_objects(image)
        checkIntersection(label, polygons, bbox)
        if config['write_bounding_boxes']=='yes' and bbox:
            out = draw_bbox(image, bbox, label, conf, None, False, polygons)
            logger.debug ('Writing out bounding boxes...')
            cv2.imwrite(filename2, out)
        match = list(filter(r.match, label))
        if len (match) == 0:
            logger.debug ('pattern match failed for {} as well'.format(filename2))
            label = []
            conf = []

if (args['time']):
    logger.debug('detection took: {}s'.format((datetime.datetime.now() - start).total_seconds()))

pred=''

seen = {}
for l,c in zip (label,conf):
    if l not in seen:
        if config['show_percent'] == 'no':
            pred = pred +l+','
        else:
            pred = pred +l+':{:.0%}'.format(c)+' '
        seen[l] = 1

if pred !='':
    pred = pred.rstrip(',')
    pred = prefix+'detected:'+pred
    logger.debug ('Prediction string:{}'.format(pred))
print (pred)
if config['delete_after_analyze']=='yes':
    os.remove(filename1)
    if filename2: 
        os.remove(filename2) 

