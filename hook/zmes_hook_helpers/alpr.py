import numpy as np
import zmes_hook_helpers.common_params as g
import zmes_hook_helpers.log as log
import cv2
import requests
import os
import imutils
import json
import base64

class ALPRPlateRecognizer:
    def __init__(self, url=None, apikey=None, regions=None, tempdir='/tmp'):
        if not apikey:
            raise ValueError ('Invalid or missing API key passed')
        self.apikey = apikey
        self.tempdir = tempdir
        self.regions = regions
        self.url = url
        g.logger.debug ('Plate Recognizer initialized with regions:{} and base url:{}'.format(self.regions, self.url))

    def setkey(self, key=None):
        self.apikey = key
        g.logger.debug ('Key changed')
    
    def stats(self):
        try:
            response = requests.get(
                            self.url+'/statistics/',
                            headers={'Authorization': 'Token ' + self.apikey}
                            )
        except requests.exceptions.RequestException as e:
            response = {'error': str(e)}
        else:
            response = response.json()
        return response

    def detect(self,object):
        bbox = []
        labels = []
        confs = []

        if not isinstance(object, str):
            g.logger.debug ('Supplied object is not a file, assuming blob and creating file')
            filename = self.tempdir + '/temp-plate-rec.jpg'
            cv2.imwrite (filename,object)
            remove_temp = True
        else:
            g.logger.debug ('supplied object is a file')
            filename = object
            remove_temp = False
        if g.config['alpr_stats'] == 'yes':
            g.logger.debug ('Plate Recognizer API usage stats: {}'.format(json.dumps(self.stats())))
        with open (filename, 'rb') as fp:
            try:
                payload = self.regions
                response = requests.post(
                        self.url+'/plate-reader/',
                        files=dict(upload=fp),
                        data=payload,
                        headers={'Authorization': 'Token ' + self.apikey})
            except requests.exceptions.RequestException as e: 
                    response = {'error': 'Plate recognizer rejected the upload. You either have a bad API key or a bad image', 'results': []}
                    g.logger.debug ('Plate recognizer rejected the upload. You either have a bad API key or a bad image')
            else:
                    response = response.json()
                    g.logger.debug ('ALPR JSON: {}'.format(response))

        rescale = False
        if g.config['resize'] != 'no':    
            img = cv2.imread(filename)
            img_new = imutils.resize(img, width=min(int(g.config['resize']), img.shape[1]))
            oldh,oldw,_ = img.shape
            newh, neww,_ = img_new.shape
            rescale = True
            xfactor = neww/oldw
            yfactor = newh/oldh
            img = None
            img_new = None
            g.logger.debug ('ALPR will use {}x{} but Yolo uses {}x{} so ALPR boxes will be scaled {}x and {}y'.format(oldw,oldh, neww, newh, xfactor, yfactor))
        else:
            xfactor = 1
            yfactor = 1

        if remove_temp:
            os.remove(filename)

        for plates in response['results']:
            label = plates['plate']
            dscore = plates['dscore']
            score = plates['score']
            if dscore >= g.config['alpr_min_dscore'] and score >= g.config['alpr_min_score']:
                x1 = round(int(plates['box']['xmin']) * xfactor)
                y1 = round(int(plates['box']['ymin']) * yfactor)
                x2 = round(int(plates['box']['xmax']) * xfactor)
                y2 = round(int(plates['box']['ymax']) * yfactor)
                labels.append(label)
                bbox.append( [x1,y1,x2,y2])
                confs.append(plates['score'])
            else:
                g.logger.debug ('ALPR: discarding plate:{} because its dscore:{}/score:{} are not in range of configured dscore:{} score:{}'.format(label,dscore,score, g.config['alpr_min_dscore'], g.config['alpr_min_score']))
        return (bbox, labels, confs)

class OpenALPR:
    def __init__(self, url=None, apikey=None, country=None, tempdir='/tmp'):
        if not apikey:
            raise ValueError ('Invalid or missing API key passed')
        self.apikey = apikey
        self.tempdir = tempdir
        self.regions = regions
        self.url = url
        g.logger.debug ('Plate Recognizer initialized with regions:{} and base url:{}'.format(self.regions, self.url))

    def setkey(self, key=None):
        self.apikey = key
        g.logger.debug ('Key changed')
    
   
    def detect(self,object):
        bbox = []
        labels = []
        confs = []

        if not isinstance(object, str):
            g.logger.debug ('Supplied object is not a file, assuming blob and creating file')
            filename = self.tempdir + '/temp-plate-rec.jpg'
            cv2.imwrite (filename,object)
            remove_temp = True
        else:
            g.logger.debug ('supplied object is a file')
            filename = object
            remove_temp = False
        
        with open (filename, 'rb') as fp:
            try:
                rurl = 'https://api.openalpr.com/v2/recognize_bytes?recognize_vehicle=1&country=%s&secret_key=%s' % (self.regions, self.apikey)
                g.logger.debug ('Trying OpenALPR with url:' + rurl)
                
                img_base64 = base64.b64encode(fp.read())

                response = requests.post(rurl, img_base64)
            except requests.exceptions.RequestException as e: 
                    response = {'error': 'Plate recognizer rejected the upload. You either have a bad API key or a bad image', 'results': []}
                    g.logger.debug ('Plate recognizer rejected the upload. You either have a bad API key or a bad image')
            else:
                    response = response.json()
                    g.logger.debug ('ALPR JSON: {}'.format(response))

        rescale = False
        if g.config['resize'] != 'no':    
            img = cv2.imread(filename)
            img_new = imutils.resize(img, width=min(int(g.config['resize']), img.shape[1]))
            oldh,oldw,_ = img.shape
            newh, neww,_ = img_new.shape
            rescale = True
            xfactor = neww/oldw
            yfactor = newh/oldh
            img = None
            img_new = None
            g.logger.debug ('ALPR will use {}x{} but Yolo uses {}x{} so ALPR boxes will be scaled {}x and {}y'.format(oldw,oldh, neww, newh, xfactor, yfactor))
        else:
            xfactor = 1
            yfactor = 1

        if remove_temp:
            os.remove(filename)

        for plates in response['results']:
            label = plates['plate']
            colour = plates['vehicle']['color'][0]['name']
            make = plates['vehicle']['make'][0]['name']
            model = plates['vehicle']['make_model'][0]['name']
            year = plates['vehicle']['year'][0]['name']
            x1 = round(int(plates['coordinates'][0]['x']) * xfactor)
            y1 = round(int(plates['coordinates'][0]['y']) * yfactor)
            x2 = round(int(plates['coordinates'][2]['x']) * xfactor)
            y2 = round(int(plates['coordinates'][2]['y']) * yfactor)
            g.logger.debug (colour)
            labels.append(label + ', ' + colour + ', ' + make + ', ' + year)
            g.logger.debug (labels)
            bbox.append( [x1,y1,x2,y2])
            confs.append(plates['confidence'])
        
        return (bbox, labels, confs)
