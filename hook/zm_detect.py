#!/usr/bin/python3

# Main detection script that loads different detection models
# look at pyzm.ml for different detectors

from __future__ import division
import sys
#lets do this _after_ log init so we log it
#import cv2
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
import subprocess
import traceback

# Modules that load cv2 will go later 
# so we can log misses
import pyzm.ZMLog as log 
import zmes_hook_helpers.utils as utils
import zmes_hook_helpers.common_params as g
from pyzm import __version__

auth_header = None

# This uses mlapi (https://github.com/pliablepixels/mlapi) to run inferencing and converts format to what is required by the rest of the code.


def remote_detect(image, model=None):
    import requests
    import cv2
    
    bbox = []
    label = []
    conf = []
    api_url = g.config['ml_gateway']
    g.logger.Info('Detecting using remote API Gateway {}'.format(api_url))
    login_url = api_url + '/login'
    object_url = api_url + '/detect/object?type='+model
    access_token = None
    global auth_header

    data_file = g.config['base_data_path'] + '/zm_login.json'
    if os.path.exists(data_file):
        g.logger.Debug(2,'Found token file, checking if token has not expired')
        with open(data_file) as json_file:
            data = json.load(json_file)
        generated = data['time']
        expires = data['expires']
        access_token = data['token']
        now = time.time()
        # lets make sure there is at least 30 secs left
        if int(now + 30 - generated) >= expires:
            g.logger.Debug(
                1,'Found access token, but it has expired (or is about to expire)'
            )
            access_token = None
        else:
            g.logger.Debug(1,'Access token is valid for {} more seconds'.format(
                int(now - generated)))
            # Get API access token
    if not access_token:
        g.logger.Debug(1,'Invoking remote API login')
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
        g.logger.Debug(2,'Writing new token for future use')
        with open(data_file, 'w') as json_file:
            wdata = {
                'token': access_token,
                'expires': data.get('expires'),
                'time': time.time()
            }
            json.dump(wdata, json_file)
            json_file.close()

    auth_header = {'Authorization': 'Bearer ' + access_token}

    if type(image) == str:
        g.logger.Debug(2, f'Reading {image} to buffer')
        image = cv2.imread(image)
        if g.config['resize'] and g.config['resize'] != 'no':
            g.logger.Debug (2,'Resizing image before sending')
            img_new = imutils.resize(image,
                                     width=min(int(g.config['resize']),
                                               image.shape[1]))
            image = img_new
    ret, jpeg = cv2.imencode('.jpg', image)
    files = {'file': ('image.jpg', jpeg.tobytes())}

    
    params = {'delete': True}
  
    #print (object_url)
    g.logger.Debug(2,f'Invoking mlapi with url:{object_url}')
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

def main_handler():
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

    ap.add_argument('-o', '--output-path',
                    help='internal testing use only - path for debug images to be written')

    ap.add_argument('-f',
                    '--file',
                    help='internal testing use only - skips event download')


    ap.add_argument('-r', '--reason', help='reason for event (notes field in ZM)')

    ap.add_argument('-n', '--notes', help='updates notes field in ZM with detections', action='store_true')

    args, u = ap.parse_known_args()
    args = vars(args)

    if not args.get('config'):
        print ('--config required')
        exit(1)

    if not args.get('file')and not args.get('eventid'):
        print ('--eventid required')
        exit(1)

    utils.get_pyzm_config(args)


    if args.get('monitorid'):
        log.init(name='zmesdetect_' + 'm' + args.get('monitorid'), override=g.config['pyzm_overrides'])
    else:
        log.init(name='zmesdetect',override=g.config['pyzm_overrides'])
    g.logger = log
    
    es_version='(?)'
    try:
        es_version=subprocess.check_output(['/usr/bin/zmeventnotification.pl', '--version']).decode('ascii')
    except:
        pass


    try:
        import cv2
    except ImportError as e:
        g.logger.Fatal (f'{e}: You might not have installed OpenCV as per install instructions. Remember, it is NOT automatically installed')

    g.logger.Info('---------| pyzm version: {}, ES version: {} , OpenCV version: {}|------------'.format(__version__, es_version, cv2.__version__))
    if args.get('version'):
        print(__version__)
        exit(0)



    # load modules that depend on cv2
    try:
        import zmes_hook_helpers.image_manip as img
        import pyzm.ml.alpr as alpr
    except Exception as e:
        g.logger.Error (f'{e}')
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
        g.logger.Info('Importing local classes for Object/Face')
        import pyzm.ml.object as object_detection
        import pyzm.ml.hog as hog
    else:
        g.logger.Info('Importing remote shim classes for Object/Face')
        from zmes_hook_helpers.apigw import ObjectRemote, FaceRemote, AlprRemote

    # now download image(s)

    if not args.get('file'):
        try:
            filename1, filename2, filename1_bbox, filename2_bbox = utils.download_files(
                args)
        except Exception as e:
            g.logger.Error(f'Error downloading files: {e}')
            g.logger.Fatal('error: Traceback:{}'.format(traceback.format_exc()))
        
        # filename_alarm will be the first frame to analyze (typically alarm)
        # filename_snapshot will be the second frame to analyze only if the first fails (typically snapshot)
    else:
        g.logger.Debug(1,'TESTING ONLY: reading image from {}'.format(args.get('file')))
        filename1 = args.get('file')
        filename1_bbox = g.config['image_path']+'/'+append_suffix(filename1, '-bbox')
        filename2 = None
        filename2_bbox = None

    start = datetime.datetime.now()

    obj_json = []
    # Read images to analyze
    image2 = None
    image1 = cv2.imread(filename1)
    if image1 is None:  # can't have this None, something went wrong
        g.logger.Error(
            'Error reading {}. It either does not exist or is invalid'.format(
                filename1))
        raise ValueError(
            'Error reading file {}. It either does not exist or is invalid'.format(
                filename1))
    oldh, oldw = image1.shape[:2]
    if filename2:  # may be none
        image2 = cv2.imread(filename2)
        if image2 is None:
            g.logger.Error(
                'Error reading {}. It either does not exist or is invalid'.format(
                    filename2))
            raise ValueError(
                'Error reading file {}. It either does not exist or is invalid'.
                format(filename2))
    # create a scaled polygon for object intersection checks
    if not g.polygons and g.config['only_triggered_zm_zones'] == 'no':
        g.polygons.append({
            'name': 'full_image',
            'value': [(0, 0), (oldw, 0), (oldw, oldh), (0, oldh)],
            'pattern': g.config.get('object_detection_pattern')

        })
        g.logger.Debug(1,
            'No polygon area specfied, so adding a full image polygon:{}'.format(
                g.polygons))
    if g.config['resize'] != 'no':
        g.logger.Debug(1,'resizing to {} before analysis...'.format(
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

    use_alpr = True if 'alpr' in g.config['detection_sequence'] else False
    g.logger.Debug(1,'User ALPR if vehicle found: {}'.format(use_alpr))
    # labels that could have license plates. See https://github.com/pjreddie/darknet/blob/master/data/coco.names

    for model in g.config['detection_sequence']:
        # instaniate the right model
        # after instantiation run all files with it,
        # so no need to do 2x instantiations

        t_start = datetime.datetime.now()

        if model == 'object':
            if g.config['ml_gateway']:
                m = ObjectRemote()
            else:
            # print ("G LOGGER {}".format(g.logger))
                m = object_detection.Object(logger=g.logger, options=g.config)
        elif model == 'hog':
            m = hog.Hog(options=g.config)
        elif model == 'face':
            if g.config['ml_gateway']:
                m = FaceRemote()
            else:
                try:
                    import pyzm.ml.face as face
                except ImportError:
                    g.logger.Error(
                        'Error importing face recognition. Make sure you did sudo -H pip3 install face_recognition'
                    )
                    raise
                
                m = face.Face(logger=g.logger, options=g.config, upsample_times=g.config['face_upsample_times'],
                            num_jitters=g.config['face_num_jitters'],
                            model=g.config['face_model'])
        elif model == 'alpr':
            if g.config['alpr_use_after_detection_only'] == 'yes':
                #g.logger.Debug (1,'Skipping ALPR as it is configured to only be used after object detection')
                continue  # we would have handled it after object
            else:
                g.logger.Info(
                    'Standalone ALPR is not supported today. Please use after object'
                )
                continue

        else:
            g.logger.Error('Invalid model {}'.format(model))
            raise ValueError('Invalid model {}'.format(model))

        #g.logger.Debug(1,'|--> model:{} init took: {}s'.format(model, (datetime.datetime.now() - t_start).total_seconds()))

        # read the detection pattern we need to apply as a filter
        pat = model + '_detection_pattern'
        try:
            g.logger.Debug(2, 'using g.config[\'{}\']={}'.format(pat, g.config[pat]))
            r = re.compile(g.config[pat])
        except re.error:
            g.logger.Error('invalid pattern {} in {}, using .*'.format(
                pat,g.config[pat]))
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

        # default order is alarm, snapshot
        frame_order = [filename2, filename1] if g.config['bestmatch_order'] == 's,a' else [filename1,filename2]

        for filename in frame_order:
            if filename is None:
                continue
            #filename = './car.jpg'
            if matched_file and filename != matched_file:
                # this will only happen if we tried model A, we found a match
                # and then we looped to model B to find more matches (that is, detection_mode is all)
                # in this case, we only want to match more models to the file we found a first match
                g.logger.Debug(1,'Skipping {} as we earlier matched {}'.format(
                    filename, matched_file))
                continue
            g.logger.Debug(1,'Using model: {} with {}'.format(model, filename))

            image = image1 if filename == filename1 else image2
            original_image = image.copy()

            if g.config['ml_gateway'] and not remote_failed:
                try:
                    b, l, c = remote_detect(original_image, model)
                except Exception as e:
                    g.logger.Error('Error executing remote API: {}'.format(e))
                    if g.config['ml_fallback_local'] == 'yes':
                        g.logger.Info('Falling back to local execution...')
                        remote_failed = True
                        if model == 'object':
                            import pyzm.ml.object as object_detection
                            m = object_detection.Object(logger=g.logger,options=g.config)
                        elif model == 'hog':
                            import pyzm.ml.hog as hog
                            m = hog.Hog(options=g.config)
                        elif model == 'face':
                            import pyzm.ml.face as face
                            m = face.Face(
                                options=g.config,
                                upsample_times=g.config['face_upsample_times'],
                                num_jitters=g.config['face_num_jitters'],
                                model=g.config['face_model'])
                        b, l, c = m.detect(original_image)
                    else:
                        raise

            else:
                b, l, c = m.detect(original_image)

            #g.logger.Debug(1,'|--> model:{} detection took: {}s'.format(model,(datetime.datetime.now() - t_start).total_seconds()))
            t_start = datetime.datetime.now()
            # Now look for matched patterns in bounding boxes
            match = list(filter(r.match, l))
            # If you want face recognition, we need to add the list of found faces
            # to the allowed list or they will be thrown away during the intersection
            # check
            if model == 'face':
            
                match = match + [g.config['unknown_face_name']]  # unknown face

                if g.config['ml_gateway'] and not remote_failed:

                    data_file = g.config[
                        'base_data_path'] + '/misc/known_face_names.json'
                    if os.path.exists(data_file):
                        g.logger.Debug(1,
                            'Found known faces list remote gateway supports. If you have trained new faces in the remote gateway, please delete this file'
                        )
                        with open(data_file) as json_file:
                            data = json.load(json_file)
                            g.logger.Debug(2,'Read from existing names: {}'.format(
                                data['names']))
                            m.set_classes(data['names'])
                    else:
                        g.logger.Debug(1,'Fetching known names from remote gateway')
                        api_url = g.config[
                            'ml_gateway'] + '/detect/object?type=face_names'
                        r = requests.post(url=api_url,
                                        headers=auth_header,
                                        params={})
                        data = r.json()
                        with open(data_file, 'w') as json_file:
                            wdata = {'names': data['names']}
                            json.dump(wdata, json_file)

                '''
                for cls in m.get_classes():
                    if not cls in match:
                        match = match + [cls]
                '''
            # now filter these with polygon areas
            #g.logger.Debug (1,"INTERIM BOX = {} {}".format(b,l))
            b, l, c = img.processFilters(b, l, c, match, model)
            if use_alpr:
                vehicle_labels = ['car', 'motorbike', 'bus', 'truck', 'boat']
                if not set(l).isdisjoint(vehicle_labels) or try_next_image:
                    # if this is true, that ,means l has vehicle labels
                    # this happens after match, so no need to add license plates to filter
                    g.logger.Debug(1,
                        'Invoking ALPR as detected object is a vehicle or, we are trying hard to look for plates...'
                    )
                    if g.config['ml_gateway']:
                        alpr_obj = AlprRemote()
                    else:
                        alpr_obj = alpr.Alpr(logger=g.logger,options=g.config)
                        

                    if g.config['ml_gateway'] and not remote_failed:
                        try:
                            alpr_b, alpr_l, alpr_c = remote_detect(original_image, 'alpr')
                        except Exception as e:
                            g.logger.Error('Error executing remote API: {}'.format(e))
                            if g.config['ml_fallback_local'] == 'yes':
                                g.logger.Info('Falling back to local execution...')
                                remote_failed = True
                                alpr_obj = alpr.Alpr(logger=g.logger,options=g.config)
                                alpr_b, alpr_l, alpr_c = alpr_obj.detect(original_image)        
                            else:
                                raise

                    else: # not ml_gateway
                        alpr_b, alpr_l, alpr_c = alpr_obj.detect(original_image)
                    alpr_b, alpr_l, alpr_c = img.getValidPlateDetections(
                        alpr_b, alpr_l, alpr_c)
                    if len(alpr_l):
                        #g.logger.Debug (1,'ALPR returned: {}, {}, {}'.format(alpr_b, alpr_l, alpr_c))
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
                            g.logger.Debug(2,
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
                        g.logger.Debug(1,
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
                        g.logger.Info(
                            'We did not find license plates, and there are no more images to try'
                        )
                        if saved_bbox:
                            g.logger.Debug(2,'Going back to matches in first image')
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
                        g.logger.Debug(1,
                            'There was no vehicle detected by object detection in this image')
                        '''
                        # For now, don't force ALPR in the next (snapshot image) 
                        # only do it if object_detection gets a vehicle there
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
                        g.logger.Debug(1,
                            'No vehicle detected, and no more images to try')
                        if saved_bbox:
                            g.logger.Debug(1,'Going back to matches in first image')
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
                g.logger.Debug(2,
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
                # g.logger.Debug (1,'ADDING {} and {}'.format(b,l))
                if not try_next_image:
                    bbox.extend(b)
                    label.extend(l)
                    conf.extend(c)
                    classes.append(m.get_classes())
                    g.logger.Info('labels found: {}'.format(l))
                    g.logger.Debug(2,
                        'match found in {}, breaking file loop...'.format(
                            filename))
                    matched_file = filename
                    break  # if we found a match, no need to process the next file
                else:
                    g.logger.Debug(2,
                        'Going to try next image before we decide the best one to use'
                    )
            else:
                g.logger.Debug(1,'No match found in {} using model:{}'.format(
                    filename, model))
            # file loop
        # model loop
        if matched_file and g.config['detection_mode'] == 'first':
            g.logger.Debug(2,
                'detection mode is set to first, breaking out of model loop...')
            break

    # all models loops, all files looped

    #g.logger.Debug (1,'FINAL LIST={} AND {}'.format(bbox,label))

    # Now create prediction string
    pred = ''

    if not matched_file:
        g.logger.Info('No patterns found using any models in all files')

    else:

        # we have matches
        if matched_file == filename1:
            #image = image1
            bbox_f = filename1_bbox
        else:
            #image = image2
            bbox_f = filename2_bbox

    
        # let's remove past detections first, if enabled 
        if g.config['match_past_detections'] == 'yes' and args.get('monitorid'):
            # point detections to post processed data set
            g.logger.Info('Removing matches to past detections')
            bbox_t, label_t, conf_t = img.processPastDetection(
                bbox, label, conf, args.get('monitorid'))
            # save current objects for future comparisons
            g.logger.Debug(1,
                'Saving detections for monitor {} for future match'.format(
                    args.get('monitorid')))
            try:
                mon_file = g.config['image_path'] + '/monitor-' + args.get(
                'monitorid') + '-data.pkl'
                f = open(mon_file, "wb")
                pickle.dump(bbox, f)
                pickle.dump(label, f)
                pickle.dump(conf, f)
                f.close()
            except Exception as e:
                g.logger.Error(f'Error writing to {mon_file}, past detections not recorded:{e}')

            bbox = bbox_t
            label = label_t
            conf = conf_t
            

        # now we draw boxes
        g.logger.Debug (2, "Drawing boxes around objects")
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
            g.logger.Debug(1,
                'Writing out debug bounding box image to {}...'.format(bbox_f))
            cv2.imwrite(bbox_f, image)

        # Do this after match past detections so we don't create an objdetect if images were discarded
        if g.config['write_image_to_zm'] == 'yes':
            if (args.get('eventpath') and len(bbox)):
                g.logger.Debug(1,'Writing detected image to {}/objdetect.jpg'.format(
                    args.get('eventpath')))
                cv2.imwrite(args.get('eventpath') + '/objdetect.jpg', image)
                jf = args.get('eventpath')+ '/objects.json'
                final_json = {'frame': frame_type, 'detections': obj_json}
                g.logger.Debug(1,'Writing JSON output to {}'.format(jf))
                try:
                    with open(jf, 'w') as jo:
                        json.dump(final_json, jo)
                        jo.close()
                except Exception as e:
                    g.logger.Error(f'Error creating {jf}:{e}')
                    
                
                if g.config['create_animation'] == 'yes':
                    g.logger.Debug(1,'animation: Creating burst...')
                    try:
                        img.createAnimation(frame_type, args.get('eventid'), args.get('eventpath')+'/objdetect', g.config['animation_types'])
                    except Exception as e:
                        g.logger.Error('Error creating animation:{}'.format(e))
                        g.logger.Error('animation: Traceback:{}'.format(traceback.format_exc()))
                    
            else:
                if not len(bbox):
                    g.logger.Debug(1,'Not writing image, as no objects recorded')
                else:
                    g.logger.Error(
                        'Could not write image to ZoneMinder as eventpath not present')


        detections = []
        seen = {}
        
        if not obj_json:
            # if we broke out early/first match
            otype = 'face' if model == 'face' else 'object'
            for idx, t_l in enumerate(label):
                #print (idx, t_l)
                obj_json.append({
                    'type': otype,
                    'label': t_l,
                    'box': bbox[idx],
                    'confidence': "{:.2f}%".format(conf[idx] * 100)
                })

        #g.logger.Debug (1,'CONFIDENCE ARRAY:{}'.format(conf))
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
            g.logger.Info('Prediction string:{}'.format(pred))
        # g.logger.Error (f"Returning THIS IS {obj_json}")
            jos = json.dumps(obj_json)
            g.logger.Debug(1,'Prediction string JSON:{}'.format(jos))
            print(pred + '--SPLIT--' + jos)

        # end of matched_file

    if g.config['delete_after_analyze'] == 'yes':
        try:
            if filename1:
                os.remove(filename1)
            if filename2:
                os.remove(filename2)
        except Exception as e:
            g.logger.Error (f'Could not delete file(s):{e}')

    if args.get('notes') and pred:
        # We want to update our DB notes with the detection string
        g.logger.Debug (1,'Updating notes for EID:{}'.format(args.get('eventid')))
        import pyzm.api as zmapi
        api_options = {
                'apiurl': g.config['api_portal'],
                'portalurl': g.config['portal'],
                'user': g.config['user'],
                'password': g.config['password'],
                'logger': g.logger # We connect the API to zmlog 
                #'logger': None, # use none if you don't want to log to ZM,
                #'disable_ssl_cert_check': True
            }
        try:
            
            myapi = zmapi.ZMApi(options=api_options)

        except Exception as e:
            g.logger.Error ('Error during login: {}'.format(str(e)))
            g.logger.Debug(2,traceback.format_exc())
            exit(0) # Let's continue with zmdetect

        url = '{}/events/{}.json'.format(g.config['api_portal'], args['eventid'])
        
        try:
            ev = myapi._make_request(url=url,  type='get')
        except Exception as e:
            g.logger.Error ('Error during event notes retrieval: {}'.format(str(e)))
            g.logger.Debug(2,traceback.format_exc())
            exit(0) # Let's continue with zmdetect

        new_notes = pred
        if ev.get('event',{}).get('Event',{}).get('Notes'): 
            old_notes = ev['event']['Event']['Notes']
            old_notes_split = old_notes.split('Motion:')
            old_d = old_notes_split[0] # old detection
            try:
                old_m = old_notes_split[1] 
            except IndexError:
                old_m = ''
            new_notes = pred + 'Motion:'+ old_m
            g.logger.Debug (1,'Replacing old note:{} with new note:{}'.format(old_notes, new_notes))
            

        payload = {}
        payload['Event[Notes]'] = new_notes
        try:
            ev = myapi._make_request(url=url, payload=payload, type='put')
        except Exception as e:
            g.logger.Error ('Error during notes update: {}'.format(str(e)))
            g.logger.Debug(2,traceback.format_exc())
            exit(0) # Let's continue with zmdetect
        

if __name__ == '__main__':
    try:
        main_handler()
    except Exception as e:
        if g.logger:
            g.logger.Fatal('Unrecoverable error:{} Traceback:{}'.format(e,traceback.format_exc()))
        else:
            print('Unrecoverable error:{} Traceback:{}'.format(e,traceback.format_exc())) 
        exit(1)