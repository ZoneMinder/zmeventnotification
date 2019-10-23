import numpy as np
import zmes_hook_helpers.common_params as g
import zmes_hook_helpers.log as log
import cv2
import requests
import os
import imutils
import json
import base64

class AlprBase:
    def __init__(self, url=None, apikey=None, tempdir='/tmp'):
        if not apikey:
            raise ValueError ('Invalid or missing API key passed')
        self.apikey = apikey
        self.tempdir = tempdir
        self.url = url

    def setkey(self, key=None):
        self.apikey = key
        g.logger.debug ('Key changed')
    
    def stats(self):
        g.logger.debug ('stats not implemented in base class')

    def detect (self, object):
        g.logger.debug ('detect not implemented in base class')

    def prepare(self, object):
        if not isinstance(object, str):
            g.logger.debug ('Supplied object is not a file, assuming blob and creating file')
            self.filename = self.tempdir + '/temp-plate-rec.jpg'
            cv2.imwrite (filename,object)
            self.remove_temp = True
        else:
            g.logger.debug ('supplied object is a file')
            self.filename = object
            self.remove_temp = False

    def getscale(self):
        if g.config['resize'] != 'no':    
            img = cv2.imread(self.filename)
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
        return (xfactor, yfactor)

class PlateRecognizer (AlprBase):
    def __init__(self, url=None, apikey=None, options={}, tempdir='/tmp'):
        AlprBase.__init__(self, url, apikey, tempdir)
        if not url: self.url = 'https://api.platerecognizer.com/v1'
        
        g.logger.debug ('PlateRecognizer ALPR initialized with options: {} and url: {}'.format(options,self.url))
        self.options = options
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
        options = self.options
        self.prepare(object)
        if options.get('stats')=='yes':
            g.logger.debug ('Plate Recognizer API usage stats: {}'.format(json.dumps(self.stats())))
        with open (self.filename, 'rb') as fp:
            try:
                payload = self.options.get('regions')
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

        (xfactor, yfactor) = self.getscale()
        

        if self.remove_temp:
            os.remove(filename)

        for plates in response['results']:
            label = plates['plate']
            dscore = plates['dscore']
            score = plates['score']
            if dscore >=options.get('min_dscore') and score >= options.get('min_score'):
                x1 = round(int(plates['box']['xmin']) * xfactor)
                y1 = round(int(plates['box']['ymin']) * yfactor)
                x2 = round(int(plates['box']['xmax']) * xfactor)
                y2 = round(int(plates['box']['ymax']) * yfactor)
                labels.append(label)
                bbox.append( [x1,y1,x2,y2])
                confs.append(plates['score'])
            else:
                g.logger.debug ('ALPR: discarding plate:{} because its dscore:{}/score:{} are not in range of configured dscore:{} score:{}'.format(label,dscore,score, options.get('min_dscore'), options.get('min_score')))
        return (bbox, labels, confs)

class OpenAlpr (AlprBase):
    def __init__(self, url=None, apikey=None, options={}, tempdir='/tmp'):
        
        AlprBase.__init__(self, url, apikey, tempdir)
        if not url: self.url = 'https://api.openalpr.com/v2/recognize'
       
        g.logger.debug ('PlateRecognizer ALPR initialized with options {} and url: {}'.format(options, self.url))
        self.options = options;

   
    def detect(self,object):
        bbox = []
        labels = []
        confs = []

        self.prepare(object)
        with open (self.filename, 'rb') as fp:
            try:
                options = self.options
                params = '';
                if options.get('country'): params = params + '&country='+options.get('country')
                if options.get('state'): params = params + '&state='+options.get('state')
                if options.get('recognize_vehicle'): params = params + '&recognize_vehicle='+str(options.get('recognize_vehicle'))

                rurl = '{}?secret_key={}{}'.format(self.url, self.apikey, params)
                g.logger.debug ('Trying OpenALPR with url:' + rurl)
                response = requests.post(rurl, files={'image':fp})
            except requests.exceptions.RequestException as e: 
                    response = {'error': 'Open ALPR rejected the upload. You either have a bad API key or a bad image', 'results': []}
                    g.logger.debug ('Open APR rejected the upload. You either have a bad API key or a bad image')
            else:
                    response = response.json()
                    g.logger.debug ('OpenALPR JSON: {}'.format(response))

        (xfactor, yfactor) = self.getscale()

        rescale = False

        if self.remove_temp:
            os.remove(filename)

        if response.get('results'):
            for plates in response.get('results'):
                label = plates['plate']
                conf = float(plates['confidence'])/100 
                if conf < options.get('min_confidence'):
                    g.logger.debug ('OpenALPR: discarding plate: {} because detected confidence {} is less than configured min confidence: {}'.format(label, conf, options.get('min_confidence') ))
                    continue

                
                if plates.get('vehicle'): # won't exist if recognize_vehicle is off
                    veh = plates.get('vehicle')
                    for attribute in ['color','make','make_model','year']:
                        if veh[attribute]:
                            label = label + ',' + veh[attribute][0]['name'] 
        
                x1 = round(int(plates['coordinates'][0]['x']) * xfactor)
                y1 = round(int(plates['coordinates'][0]['y']) * yfactor)
                x2 = round(int(plates['coordinates'][2]['x']) * xfactor)
                y2 = round(int(plates['coordinates'][2]['y']) * yfactor)
                labels.append(label)
                bbox.append( [x1,y1,x2,y2])
                confs.append(conf)
        
        return (bbox, labels, confs)
