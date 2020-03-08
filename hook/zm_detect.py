#!/usr/bin/python3

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
import pickle
import json
import time
import requests
#import hashlib

import zmes_hook_helpers.log as log
import zmes_hook_helpers.utils as utils
import zmes_hook_helpers.image_manip as img
import zmes_hook_helpers.common_params as g

import zmes_hook_helpers.alpr as alpr
from zmes_hook_helpers.__init__ import __version__

auth_header = None
# This uses mlapi (https://github.com/pliablepixels/mlapi) to run inferencing and converts format to what is required by the rest of the code.


def remote_detect(image, model=None):
    import requests
    bbox = []
    label = []
    conf = []
    api_url = g.config['ml_gateway']
    g.logger.info('Detecting using remote API Gateway {}'.format(api_url))
    login_url = api_url + '/login'
    object_url = api_url + '/detect/object'
    access_token = None
    global auth_header

    if model == 'face':
        object_url += '?type=face'

    data_file = g.config['base_data_path'] + '/zm_login.json'
    if os.path.exists(data_file):
        g.logger.debug('Found token file, checking if token has not expired')
        with open(data_file) as json_file:
            data = json.load(json_file)
        generated = data['time']
        expires = data['expires']
        access_token = data['token']
        now = time.time()
        # lets make sure there is at least 30 secs left
        if int(now + 30 - generated) >= expires:
            g.logger.debug(
                'Found access token, but it has expired (or is about to expire)'
            )
            access_token = None
        else:
            g.logger.debug('Access token is valid for {} more seconds'.format(
                int(now - generated)))
            # Get API access token
    if not access_token:
        g.logger.debug('Invoking remote API login')
        r = requests.post(url=login_url,
                          data=json.dumps({
                              'username': g.config['ml_user'],
                              'password': g.config['ml_password']
                          }),
                          headers={'content-type': 'application/json'})
        data = r.json()
        access_token = data.get('access_token')
        if not access_token:
            raise ValueError('Error getting remote API token {}'.format(data))
            return
        g.logger.debug('Writing new token for future use')
        with open(data_file, 'w') as json_file:
            wdata = {
                'token': access_token,
                'expires': data.get('expires'),
                'time': time.time()
            }
            json.dump(wdata, json_file)

    auth_header = {'Authorization': 'Bearer ' + access_token}
    ret, jpeg = cv2.imencode('.jpg', image)
    files = {'file': ('image.jpg', jpeg.tobytes())}

    params = {
        'delete': True,
    }
    #print (object_url)
    r = requests.post(url=object_url,
                      headers=auth_header,
                      params=params,
                      files=files)
    data = r.json()

    for d in data:

        label.append(d.get('label'))
        conf.append(float(d.get('confidence').strip('%')) / 100)
        box = d.get('box')
        bbox.append(d.get('box'))

        #print (bbox, label, conf)
    return bbox, label, conf


def append_suffix(filename, token):
    f, e = os.path.splitext(filename)
    return f + token + e


# main handler

# set up logging to syslog

# construct the argument parse and parse the arguments
ap = argparse.ArgumentParser()
ap.add_argument('-c', '--config', help='config file with path')
ap.add_argument('-e', '--eventid', help='event ID to retrieve')
ap.add_argument('-p',
                '--eventpath',
                help='path to store object image file',
                default='')
ap.add_argument('-m', '--monitorid', help='monitor id - needed for mask')
ap.add_argument('-v',
                '--version',
                help='print version and quit',
                action='store_true')

ap.add_argument('-f',
                '--file',
                help='internal testing use only - skips event download')

args, u = ap.parse_known_args()
args = vars(args)

if args['monitorid']:
    log.init(process_name='zmesdetect_' + 'm' + args['monitorid'])
else:
    log.init(process_name='zmesdetect')

g.logger.info('---------| app version: {} |------------'.format(__version__))
if args['version']:
    print(__version__)
    exit(0)


if not args['config'] or not args['eventid']:
    print ('--config and --eventid are required')
    exit(1)

g.polygons = []

# process config file
g.ctx = ssl.create_default_context()

utils.process_config(args, g.ctx)

# misc came later, so lets be safe
if not os.path.exists(g.config['base_data_path'] + '/misc/'):
    try:
        os.makedirs(g.config['base_data_path'] + '/misc/')
    except FileExistsError:
        pass  # if two detects run together with a race here

if not g.config['ml_gateway']:
    g.logger.info('Importing local classes for Yolo/Face')
    import zmes_hook_helpers.yolo as yolo
    import zmes_hook_helpers.hog as hog
else:
    g.logger.info('Importing remote shim classes for Yolo/Face')
    from zmes_hook_helpers.apigw import YoloRemote, FaceRemote

# now download image(s)

if not args['file']:
    filename1, filename2, filename1_bbox, filename2_bbox = utils.download_files(
        args)

    # filename_alarm will be the first frame to analyze (typically alarm)
    # filename_snapshot will be the second frame to analyze only if the first fails (typically snapshot)
else:
    g.logger.debug('TESTING ONLY: reading image from {}'.format(args['file']))
    filename1 = args['file']
    filename1_bbox = append_suffix(filename1, '-bbox')
    filename2 = None
    filename2_bbox = None

start = datetime.datetime.now()

obj_json = []
# Read images to analyze
image2 = None
image1 = cv2.imread(filename1)
if image1 is None:  # can't have this None, something went wrong
    g.logger.error(
        'Error reading {}. It either does not exist or is invalid'.format(
            filename1))
    raise ValueError(
        'Error reading file {}. It either does not exist or is invalid'.format(
            filename1))
oldh, oldw = image1.shape[:2]
if filename2:  # may be none
    image2 = cv2.imread(filename2)
    if image2 is None:
        g.logger.error(
            'Error reading {}. It either does not exist or is invalid'.format(
                filename2))
        raise ValueError(
            'Error reading file {}. It either does not exist or is invalid'.
            format(filename2))
# create a scaled polygon for object intersection checks
if not g.polygons:
    g.polygons.append({
        'name': 'full_image',
        'value': [(0, 0), (oldw, 0), (oldw, oldh), (0, oldh)]
    })
    g.logger.debug(
        'No polygon area specfied, so adding a full image polygon:{}'.format(
            g.polygons))
if g.config['resize'] != 'no':
    g.logger.debug('resizing to {} before analysis...'.format(
        g.config['resize']))
    image1 = imutils.resize(image1,
                            width=min(int(g.config['resize']),
                                      image1.shape[1]))
    if image2 is not None:
        image2 = imutils.resize(image2,
                                width=min(int(g.config['resize']),
                                          image2.shape[1]))

    newh, neww = image1.shape[:2]
    utils.rescale_polygons(neww / oldw, newh / oldh)

# Apply all configured models to each file

matched_file = None
bbox = []
label = []
conf = []
classes = []

use_alpr = True if 'alpr' in g.config['models'] else False
g.logger.debug('User ALPR if vehicle found: {}'.format(use_alpr))
# labels that could have license plates. See https://github.com/pjreddie/darknet/blob/master/data/coco.names

for model in g.config['models']:
    # instaniate the right model
    # after instantiation run all files with it,
    # so no need to do 2x instantiations

    t_start = datetime.datetime.now()

    if model == 'yolo':
        if g.config['ml_gateway']:
            m = YoloRemote()
        else:
            m = yolo.Yolo()
    elif model == 'hog':
        m = hog.Hog()
    elif model == 'face':
        if g.config['ml_gateway']:
            m = FaceRemote()
        else:
            try:
                import zmes_hook_helpers.face as face
            except ImportError:
                g.logger.error(
                    'Error importing face recognition. Make sure you did sudo -H pip3 install face_recognition'
                )
                raise

            m = face.Face(upsample_times=g.config['face_upsample_times'],
                          num_jitters=g.config['face_num_jitters'],
                          model=g.config['face_model'])
    elif model == 'alpr':
        if g.config['alpr_use_after_detection_only'] == 'yes':
            #g.logger.debug ('Skipping ALPR as it is configured to only be used after object detection')
            continue  # we would have handled it after YOLO
        else:
            g.logger.info(
                'Standalone ALPR is not supported today. Please use after yolo'
            )
            continue

    else:
        g.logger.error('Invalid model {}'.format(model))
        raise ValueError('Invalid model {}'.format(model))

    #g.logger.debug('|--> model:{} init took: {}s'.format(model, (datetime.datetime.now() - t_start).total_seconds()))

    # read the detection pattern we need to apply as a filter
    try:
        r = re.compile(g.config['detect_pattern'])
    except re.error:
        g.logger.error('invalid pattern {}, using .*'.format(
            g.config['detect_pattern']))
        r = re.compile('.*')

    t_start = datetime.datetime.now()
    try_next_image = False  # take the best of both images, currently used only by alpr
    # temporary holders, incase alpr is used but not found
    saved_bbox = []
    saved_labels = []
    saved_conf = []
    saved_classes = []
    saved_image = None
    saved_file = None
    # Apply the model to all files
    remote_failed = False
    for filename in [filename1, filename2]:
        if filename is None:
            continue
        #filename = './car.jpg'
        if matched_file and filename != matched_file:
            # this will only happen if we tried model A, we found a match
            # and then we looped to model B to find more matches (that is, detection_mode is all)
            # in this case, we only want to match more models to the file we found a first match
            g.logger.debug('Skipping {} as we earlier matched {}'.format(
                filename, matched_file))
            continue
        g.logger.debug('Using model: {} with {}'.format(model, filename))

        image = image1 if filename == filename1 else image2

        if g.config['ml_gateway'] and not remote_failed:
            try:
                b, l, c = remote_detect(image, model)
            except Exception as e:
                g.logger.error('Error executing remote API: {}'.format(e))
                if g.config['ml_fallback_local'] == 'yes':
                    g.logger.info('Falling back to local execution...')
                    remote_failed = True
                    if model == 'yolo':
                        import zmes_hook_helpers.yolo as yolo
                        m = yolo.Yolo()
                    elif model == 'hog':
                        import zmes_hook_helpers.hog as hog
                        m = hog.Hog()
                    elif model == 'face':
                        import zmes_hook_helpers.face as face
                        m = face.Face(
                            upsample_times=g.config['face_upsample_times'],
                            num_jitters=g.config['face_num_jitters'],
                            model=g.config['face_model'])
                    b, l, c = m.detect(image)
                else:
                    raise

        else:
            b, l, c = m.detect(image)

        #g.logger.debug('|--> model:{} detection took: {}s'.format(model,(datetime.datetime.now() - t_start).total_seconds()))
        t_start = datetime.datetime.now()
        # Now look for matched patterns in bounding boxes
        match = list(filter(r.match, l))
        # If you want face recognition, we need to add the list of found faces
        # to the allowed list or they will be thrown away during the intersection
        # check
        if model == 'face':
            g.logger.debug('Appending known faces to filter list')
            match = match + [g.config['unknown_face_name']]  # unknown face

            if g.config['ml_gateway'] and not remote_failed:

                data_file = g.config[
                    'base_data_path'] + '/misc/known_face_names.json'
                if os.path.exists(data_file):
                    g.logger.debug(
                        'Found known faces list remote gateway supports. If you have trained new faces in the remote gateway, please delete this file'
                    )
                    with open(data_file) as json_file:
                        data = json.load(json_file)
                        g.logger.debug('Read from existing names: {}'.format(
                            data['names']))
                        m.set_classes(data['names'])
                else:
                    g.logger.debug('Fetching known names from remote gateway')
                    api_url = g.config[
                        'ml_gateway'] + '/detect/object?type=face_names'
                    r = requests.post(url=api_url,
                                      headers=auth_header,
                                      params={})
                    data = r.json()
                    with open(data_file, 'w') as json_file:
                        wdata = {'names': data['names']}
                        json.dump(wdata, json_file)

            for cls in m.get_classes():
                if not cls in match:
                    match = match + [cls]

        # now filter these with polygon areas
        #g.logger.debug ("INTERIM BOX = {} {}".format(b,l))
        b, l, c = img.processFilters(b, l, c, match)
        if use_alpr:
            vehicle_labels = ['car', 'motorbike', 'bus', 'truck', 'boat']
            if not set(l).isdisjoint(vehicle_labels) or try_next_image:
                # if this is true, that ,means l has vehicle labels
                # this happens after match, so no need to add license plates to filter
                g.logger.debug(
                    'Invoking ALPR as detected object is a vehicle or, we are trying hard to look for plates...'
                )
                if g.config['alpr_service'] == 'plate_recognizer':
                    options = {
                        'regions': g.config['platerec_regions'],
                        'stats': g.config['platerec_stats'],
                        'min_dscore': g.config['platerec_min_dscore'],
                        'min_score': g.config['platerec_min_score'],
                    }
                    alpr_obj = alpr.PlateRecognizer(
                        url=g.config['alpr_url'],
                        apikey=g.config['alpr_key'],
                        options=options)
                elif g.config['alpr_service'] == 'open_alpr':
                    options = {
                        'min_confidence': g.config['openalpr_min_confidence'],
                        'country': g.config['openalpr_country'],
                        'state': g.config['openalpr_state'],
                        'recognize_vehicle':
                        g.config['openalpr_recognize_vehicle']
                    }
                    alpr_obj = alpr.OpenAlpr(url=g.config['alpr_url'],
                                             apikey=g.config['alpr_key'],
                                             options=options)
                elif g.config['alpr_service'] == 'open_alpr_cmdline':
                    options = {
                        'min_confidence': g.config['openalpr_cmdline_min_confidence'],
                    }
                    alpr_obj = alpr.OpenAlprCmdLine(cmd=g.config['openalpr_cmdline_binary'],
                                             options=options)
                else:
                    raise ValueError('ALPR service "{}" not known'.format(
                        g.config['alpr_service']))
                # don't pass resized image - may be too small
                alpr_b, alpr_l, alpr_c = alpr_obj.detect(filename)
                alpr_b, alpr_l, alpr_c = img.getValidPlateDetections(
                    alpr_b, alpr_l, alpr_c)
                if len(alpr_l):
                    #g.logger.debug ('ALPR returned: {}, {}, {}'.format(alpr_b, alpr_l, alpr_c))
                    try_next_image = False
                    # First get non plate objects
                    for idx, t_l in enumerate(l):
                        otype = 'face' if model == 'face' else 'object'
                        obj_json.append({
                            'type':
                            otype,
                            'label':
                            t_l,
                            'box':
                            b[idx],
                            'confidence':
                            "{:.2f}%".format(c[idx] * 100)
                        })
                    # Now add plate objects
                    for i, al in enumerate(alpr_l):
                        g.logger.info(
                            'ALPR Found {} at {} with score:{}'.format(
                                al, alpr_b[i], alpr_c[i]))
                        b.append(alpr_b[i])
                        l.append(al)
                        c.append(alpr_c[i])
                        obj_json.append({
                            'type':
                            'licenseplate',
                            'label':
                            al,
                            'box':
                            alpr_b[i],
                            #'confidence': alpr_c[i]
                            'confidence':
                            "{:.2f}%".format(alpr_c[i] * 100)
                        })
                elif filename == filename1 and filename2:  # no plates, but another image to try
                    g.logger.debug(
                        'We did not find license plates in vehicles, but there is another image to try'
                    )
                    saved_bbox = b
                    saved_labels = l
                    saved_conf = c
                    saved_classes = m.get_classes()
                    saved_image = image.copy()
                    saved_file = filename
                    try_next_image = True
                else:  # no plates, no more to try
                    g.logger.info(
                        'We did not find license plates, and there are no more images to try'
                    )
                    if saved_bbox:
                        g.logger.debug('Going back to matches in first image')
                        b = saved_bbox
                        l = saved_labels
                        c = saved_conf
                        image = saved_image
                        filename = saved_file
                        # store non plate objects
                        otype = 'face' if model == 'face' else 'object'
                        for idx, t_l in enumerate(l):
                            obj_json.append({
                                'type':
                                otype,
                                'label':
                                t_l,
                                'box':
                                b[idx],
                                'confidence':
                                "{:.2f}%".format(c[idx] * 100)
                            })
                    try_next_image = False
            else:  # objects, no vehicles
                if filename == filename1 and filename2:
                    g.logger.debug(
                        'There was no vehicle detected by Yolo in this image')
                    '''
                    # For now, don't force ALPR in the next (snapshot image) 
                    # only do it if yolo gets a vehicle there
                    # may change this later
                    try_next_image = True
                    saved_bbox = b
                    saved_labels = l
                    saved_conf = c
                    saved_classes = m.get_classes()
                    saved_image = image.copy()
                    saved_file = filename
                    '''
                else:
                    g.logger.debug(
                        'No vehicle detected, and no more images to try')
                    if saved_bbox:
                        g.logger.debug('Going back to matches in first image')
                        b = saved_bbox
                        l = saved_labels
                        c = saved_conf
                        image = saved_image
                        filename = saved_file
                    try_next_image = False
                    otype = 'face' if model == 'face' else 'object'
                    for idx, t_l in enumerate(l):
                        obj_json.append({
                            'type':
                            'object',
                            'label':
                            t_l,
                            'box':
                            b[idx],
                            'confidence':
                            "{:.2f}%".format(c[idx] * 100)
                        })
        else:  # usealpr
            g.logger.debug(
                'ALPR not in use, no need for look aheads in processing')
            # store objects
            otype = 'face' if model == 'face' else 'object'
            for idx, t_l in enumerate(l):
                obj_json.append({
                    'type': otype,
                    'label': t_l,
                    'box': b[idx],
                    'confidence': "{:.2f}%".format(c[idx] * 100)
                })
        if b:
            # g.logger.debug ('ADDING {} and {}'.format(b,l))
            if not try_next_image:
                bbox.extend(b)
                label.extend(l)
                conf.extend(c)
                classes.append(m.get_classes())
                g.logger.info('labels found: {}'.format(l))
                g.logger.debug(
                    'match found in {}, breaking file loop...'.format(
                        filename))
                matched_file = filename
                break  # if we found a match, no need to process the next file
            else:
                g.logger.debug(
                    'Going to try next image before we decide the best one to use'
                )
        else:
            g.logger.debug('No match found in {} using model:{}'.format(
                filename, model))
        # file loop
    # model loop
    if matched_file and g.config['detection_mode'] == 'first':
        g.logger.debug(
            'detection mode is set to first, breaking out of model loop...')
        break

# all models loops, all files looped

#g.logger.debug ('FINAL LIST={} AND {}'.format(bbox,label))

if not matched_file:
    g.logger.info('No patterns found using any models in all files')

else:

    # we have matches
    if matched_file == filename1:
        #image = image1
        bbox_f = filename1_bbox
    else:
        #image = image2
        bbox_f = filename2_bbox

    #for idx, b in enumerate(bbox):
    #g.logger.debug ("DRAWING {}".format(b))

    out = img.draw_bbox(image, bbox, label, classes, conf, None,
                        g.config['show_percent'] == 'yes')
    image = out

    if g.config['frame_id'] == 'bestmatch':
        if matched_file == filename1:
            prefix = '[a] '  # we will first analyze alarm
            frame_type = 'alarm'
        else:
            prefix = '[s] '
            frame_type = 'snapshot'
    else:
        prefix = '[x] '
        frame_type = g.config['frame_id']

    if g.config['write_debug_image'] == 'yes':
        g.logger.debug(
            'Writing out debug bounding box image to {}...'.format(bbox_f))
        cv2.imwrite(bbox_f, image)

    

    if g.config['match_past_detections'] == 'yes' and args['monitorid']:
        # point detections to post processed data set
        g.logger.info('Removing matches to past detections')
        bbox_t, label_t, conf_t = img.processPastDetection(
            bbox, label, conf, args['monitorid'])
        # save current objects for future comparisons
        g.logger.debug(
            'Saving detections for monitor {} for future match'.format(
                args['monitorid']))
        mon_file = g.config['image_path'] + '/monitor-' + args[
            'monitorid'] + '-data.pkl'
        f = open(mon_file, "wb")
        pickle.dump(bbox, f)
        pickle.dump(label, f)
        pickle.dump(conf, f)
        bbox = bbox_t
        label = label_t
        conf = conf_t
    
    # Do this after match past detections so we don't create an objdetect if images were discarded
    if g.config['write_image_to_zm'] == 'yes':
        if (args['eventpath'] and len(bbox)):
            g.logger.debug('Writing detected image to {}/objdetect.jpg'.format(
                args['eventpath']))
            cv2.imwrite(args['eventpath'] + '/objdetect.jpg', image)
            jf = args['eventpath'] + '/objects.json'
            final_json = {'frame': frame_type, 'detections': obj_json}
            g.logger.debug('Writing JSON output to {}'.format(jf))
            with open(jf, 'w') as jo:
                json.dump(final_json, jo)

        else:
            g.logger.error(
                'Could not write image to ZoneMinder as eventpath not present')


    # Now create prediction string
    pred = ''
    detections = []
    seen = {}

    if not obj_json:
        # if we broke out early/first match
        otype = 'face' if model == 'face' else 'object'
        for idx, t_l in enumerate(label):
            obj_json.append({
                'type': otype,
                'label': t_l,
                'box': bbox[idx],
                'confidence': "{:.2f}%".format(c[idx] * 100)
            })

    #g.logger.debug ('CONFIDENCE ARRAY:{}'.format(conf))
    for idx, l in enumerate(label):
        if l not in seen:
            if g.config['show_percent'] == 'no':
                pred = pred + l + ','
            else:
                pred = pred + l + ':{:.0%}'.format(conf[idx]) + ' '
            seen[l] = 1

    if pred != '':
        pred = pred.rstrip(',')
        pred = prefix + 'detected:' + pred
        g.logger.info('Prediction string:{}'.format(pred))
        jos = json.dumps(obj_json)
        g.logger.debug('Prediction string JSON:{}'.format(jos))

        print(pred + '--SPLIT--' + jos)

    # end of matched_file

if g.config['delete_after_analyze'] == 'yes':
    if filename1:
        os.remove(filename1)
    if filename2:
        os.remove(filename2)
