import numpy as np
import zmes_hook_helpers.common_params as g
import zmes_hook_helpers.log as log
import sys
import cv2
from imutils.object_detection import non_max_suppression


# Class to handle HOG based detection

class Hog:

    def __init__(self):
        self.hog = cv2.HOGDescriptor()
        self.hog.setSVMDetector(cv2.HOGDescriptor_getDefaultPeopleDetector())
        self.winStride = g.config['stride']
        self.padding = g.config['padding']
        self.scale = float(g.config['scale'])
        self.meanShift = True if int(g.config['mean_shift']) > 0 else False
        g.logger.debug('Initializing HOG');

    def get_classes(self):
        return ['person']

    def detect(self, image):
        r, w = self.hog.detectMultiScale(image, winStride=self.winStride, padding=self.padding, scale=self.scale, useMeanshiftGrouping=self.meanShift)
        labels = []
        classes = []
        conf = []

        for i in r:
            labels.append('person')
            classes.append('person')
            conf.append(1)

        return r, labels, conf
