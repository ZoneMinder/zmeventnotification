import numpy as np
import zmes_hook_helpers.common_params as g
import zmes_hook_helpers.log as log
import cv2
import requests
import os
import imutils

class ALPRPlateRecognizer:
    def __init__(self, apikey=None, tempdir='/tmp'):
        if not apikey:
            raise ValueError ('Invalid or missing API key passed')
        self.apikey = apikey
        self.tempdir = tempdir
        g.logger.debug ('Plate Recognizer initialized')

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
                response = requests.post(
                        'https://api.platerecognizer.com/v1/plate-reader/',
                        files=dict(upload=fp),
                        headers={'Authorization': 'Token ' + self.apikey})
            except requests.exceptions.RequestException as e: 
                    response = {'error': 'Plate recognizer rejected the upload. You either have a bad API key or a bad image', 'results': []}
                    g.logger.debug ('Plate recognizer rejected the upload. You either have a bad API key or a bad image')
            else:
                    response = response.json()
                    g.logger.debug ('ALPR JSON: {}'.format(response))

        rescale = False
        if g.config['resize']:    
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
            x1 = round(int(plates['box']['xmin']) * xfactor)
            y1 = round(int(plates['box']['ymin']) * yfactor)
            x2 = round(int(plates['box']['xmax']) * xfactor)
            y2 = round(int(plates['box']['ymax']) * yfactor)
            labels.append(label)
            bbox.append( [x1,y1,x2,y2])
            confs.append(plates['score'])
        return (bbox, labels, confs)