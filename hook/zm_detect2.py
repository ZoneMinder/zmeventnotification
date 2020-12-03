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
import pyzm.helpers.utils as pyzmutils
import zmes_hook_helpers.common_params as g
from pyzm import __version__ as pyzm_version
from zmes_hook_helpers import __version__ as hooks_version


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
    if not e:
        e = '.jpg'
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
    ap.add_argument('-d', '--debug', help='enables debug on console', action='store_true')

    args, u = ap.parse_known_args()
    args = vars(args)

    if args.get('version'):
        print('hooks:{} pyzm:{}'.format(hooks_version, pyzm_version))
        exit(0)

    if not args.get('config'):
        print ('--config required')
        exit(1)

    if not args.get('file')and not args.get('eventid'):
        print ('--eventid required')
        exit(1)

    utils.get_pyzm_config(args)

    if args.get('debug'):
        g.config['pyzm_overrides']['dump_console'] = True
        g.config['pyzm_overrides']['log_debug'] = True
        g.config['pyzm_overrides']['log_level_debug'] = 4
        g.config['pyzm_overrides']['log_debug_target'] = None

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

    g.logger.Info('---------| pyzm version:{}, hook version:{},  ES version:{} , OpenCV version:{}|------------'.format(pyzm_version, hooks_version, es_version, cv2.__version__))
   

    
    # load modules that depend on cv2
    try:
        import zmes_hook_helpers.image_manip as img
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


    start = datetime.datetime.now()

    obj_json = []

    from pyzm.ml.detect_sequence import DetectSequence
    import pyzm.api as zmapi

    api_options  = {
    'apiurl': g.config['api_portal'],
    'portalurl': g.config['portal'],
    'user': g.config['user'],
    'password': g.config['password'] ,
    'logger': g.logger, # use none if you don't want to log to ZM,
    #'disable_ssl_cert_check': True
    }

    zmapi = zmapi.ZMApi(options=api_options)
    stream = args.get('eventid') or args.get('file')

    ml_options = {
        'general': {
            'model_sequence': 'object,face,alpr',
            #'model_sequence': 'object,face',        
        },
    
        'object': {
            'general':{
                'same_model_sequence_strategy': 'first' # 'first' 'most', 'most_unique'
            },
            'sequence': [{
                #First run on TPU
                'object_weights':'/var/lib/zmeventnotification/models/coral_edgetpu/ssd_mobilenet_v2_coco_quant_postprocess_edgetpu.tflite',
                'object_labels': '/var/lib/zmeventnotification/models/coral_edgetpu/coco_indexed.names',
                'object_min_confidence': 0.3,
                'object_framework':'coral_edgetpu'
            },
            {
                # YoloV4 on GPU if TPU fails (because sequence strategy is 'first')
                'object_config':'/var/lib/zmeventnotification/models/yolov4/yolov4.cfg',
                'object_weights':'/var/lib/zmeventnotification/models/yolov4/yolov4.weights',
                'object_labels': '/var/lib/zmeventnotification/models/yolov4/coco.names',
                'object_min_confidence': 0.3,
                'object_framework':'opencv',
                'object_processor': 'gpu'
            }]
        },
        'face': {
            'general':{
                'same_model_sequence_strategy': 'first'
            },
            'sequence': [{
                'face_detection_framework': 'dlib',
                'known_images_path': '/var/lib/zmeventnotification/known_faces',
                'face_model': 'cnn',
                'face_train_model': 'cnn',
                'face_recog_dist_threshold': 0.6,
                'face_num_jitters': 1,
                'face_upsample_times':1
            }]
        },

        'alpr': {
            'general':{
                'same_model_sequence_strategy': 'first',
                'pre_existing_labels':['car', 'motorbike', 'bus', 'truck', 'boat'],

            },
            'sequence': [{
                'alpr_api_type': 'cloud',
                'alpr_service': 'plate_recognizer',
                'alpr_key': g.config['alpr_key'],
                'platrec_stats': 'no',
                'platerec_min_dscore': 0.1,
                'platerec_min_score': 0.2,
            }]
        }
    } # ml_options

    stream_options = {
            'api': zmapi,
            'download': False,
            'frame_set': 'alarm,snapshot',
            'strategy': 'most_models',
            'polygons': g.polygons,
            'resize': int(g.config['resize']) if g.config['resize'] != 'no' else None

    }

    m = DetectSequence(options=ml_options, logger=g.logger)
    matched_data,all_data = m.detect_stream(stream=stream, options=stream_options)
    #print(f'ALL FRAMES: {all_data}\n\n')
    #print (f"SELECTED FRAME {matched_data['frame_id']}, size {matched_data['image_dimensions']} with LABELS {matched_data['labels']} {matched_data['boxes']} {matched_data['confidences']}")
    
    '''
     matched_data = {
            'boxes': matched_b,
            'labels': matched_l,
            'confidences': matched_c,
            'frame_id': matched_frame_id,
            'image_dimensions': self.media.image_dimensions(),
            'image': matched_frame_img
        }
    '''

    obj_json = {
        'labels': matched_data['labels'],
        'boxes': matched_data['boxes'],
        'frame_id': matched_data['frame_id'],
        'confidences': matched_data['confidences'],
        'image_dimensions': matched_data['image_dimensions']
    }

    # 'confidences': ["{:.2f}%".format(item * 100) for item in matched_data['confidences']],
    
    detections = []
    seen = {}
    pred=''
    prefix = ''

    if matched_data['frame_id'] == 'snapshot':
        prefix = '[s] '
    elif matched_data['frame_id'] == 'alarm':
        prefix = '[a] '
    else:
        prefix = '[x] '
        #g.logger.Debug (1,'CONFIDENCE ARRAY:{}'.format(conf))
    for idx, l in enumerate(matched_data['labels']):
        if l not in seen:
            if g.config['show_percent'] == 'no':
                pred = pred + l + ','
            else:
                pred = pred + l + ':{:.0%}'.format(matched_data['confidences'][idx]) + ' '
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
    
        if g.config['write_debug_image'] == 'yes':
            debug_image = pyzmutils.draw_bbox(matched_data['image'],matched_data['boxes'], matched_data['labels'],
                                            matched_data['confidences'],g.polygons)
            filename_debug = g.config['image_path']+'/'+os.path.basename(append_suffix(stream, '-{}-debug'.format(matched_data['frame_id'])))
            g.logger.Debug (1,'Writing bound boxes to debug image: {}'.format(filename_debug))
            cv2.imwrite(filename_debug,debug_image)

    if args.get('notes') and pred:
        url = '{}/events/{}.json'.format(g.config['api_portal'], args['eventid'])
        try:
            ev = zmapi._make_request(url=url,  type='get')
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
            ev = zmapi._make_request(url=url, payload=payload, type='put')
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