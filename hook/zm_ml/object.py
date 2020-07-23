import numpy as np
import zm_ml.common_params as g
import zm_ml.log as log
import sys
import cv2
import time
import datetime
import re

# Class to handle Yolo based detection




class Object:

    # The actual CNN object detection code
    # opencv DNN code credit: https://github.com/arunponnusamy/cvlib

    def __init__(self):

        self.model = None
        if g.config['object_framework'] == 'opencv':
            import zm_ml.yolo as yolo
            self.model =  yolo.Yolo()
            

        elif g.config['object_framework'] == 'coral_edgetpu':
            import zm_ml.coral_edgetpu as tpu
            self.model = tpu.Tpu()
            return self.model

        else:
            raise ValueError ('Invalid object_framework:{}'.format(g.config['object_framework']))

    def get_model(self):
            return self.model
       