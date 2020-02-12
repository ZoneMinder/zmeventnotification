import numpy as np
import zmes_hook_helpers.common_params as g
import zmes_hook_helpers.log as log
import sys
import cv2
import time
import datetime

# Class to handle Yolo based detection


class Yolo:

# The actual CNN object detection code
# opencv DNN code credit: https://github.com/arunponnusamy/cvlib

    def __init__(self):
        self.initialize = True
        self.net = None
        self.classes = None

        

    def populate_class_labels(self):
        if g.config['yolo_type'] == 'tiny':
            class_file_abs_path = g.config['tiny_labels']
        else:
            class_file_abs_path = g.config['labels']
        f = open(class_file_abs_path, 'r')
        self.classes = [line.strip() for line in f.readlines()]

    def get_classes(self):
        return self.classes

    def get_output_layers(self):
        layer_names = self.net.getLayerNames()
        output_layers = [layer_names[i[0] - 1] for i in self.net.getUnconnectedOutLayers()]
        return output_layers

    def detect(self, image):
        
        Height, Width = image.shape[:2]
        modelW = 416
        modelH = 416
        
        g.logger.debug ('|---------- YOLO (input image: {}w*{}h, resized to: {}w*{}h) ----------|'.format(Width, Height, modelW, modelH))
        scale = 0.00392 # 1/255, really. Normalize inputs.

        if g.config['yolo_type'] == 'tiny':
            config_file_abs_path = g.config['tiny_config']
            weights_file_abs_path = g.config['tiny_weights']
        else:
            config_file_abs_path = g.config['config']
            weights_file_abs_path = g.config['weights']

        if self.initialize:
            g.logger.debug('Initializing Yolo')
            g.logger.debug('config:{}, weights:{}'.format(config_file_abs_path, weights_file_abs_path))
            start = datetime.datetime.now()
            self.populate_class_labels()
            self.net = cv2.dnn.readNet(weights_file_abs_path, config_file_abs_path)
            #self.net = cv2.dnn.readNetFromDarknet(config_file_abs_path, weights_file_abs_path)


            if g.config['use_opencv_dnn_cuda']=='yes':
                (maj,minor,patch) = cv2.__version__.split('.')
                min_ver = int (maj+minor)
                if min_ver < 42:
                    g.logger.error ('Not setting CUDA backend for OpenCV DNN')
                    g.logger.error ('You are using OpenCV version {} which does not support CUDA for DNNs. A minimum of 4.2 is required. See https://www.pyimagesearch.com/2020/02/03/how-to-use-opencvs-dnn-module-with-nvidia-gpus-cuda-and-cudnn/ on how to compile and install openCV 4.2'.format(cv2.__version__))
                else:
                    g.logger.debug ('Setting CUDA backend for OpenCV. If you did not set your CUDA_ARCH_BIN correctly during OpenCV compilation, you will get errors during detection related to invalid device/make_policy')
                    self.net.setPreferableBackend(cv2.dnn.DNN_BACKEND_CUDA)
                    self.net.setPreferableTarget(cv2.dnn.DNN_TARGET_CUDA)
            else:
                g.logger.debug ("Not using CUDA backend")

            diff_time = (datetime.datetime.now() - start).microseconds/1000
            g.logger.debug ('YOLO initialization (loading model from disk) took: {} milliseconds'.format(diff_time))
            self.initialize = False
            

        start = datetime.datetime.now()
        ln = self.net.getLayerNames()
        ln = [ln[i[0] - 1] for i in self.net.getUnconnectedOutLayers()]
        blob = cv2.dnn.blobFromImage(image, scale, (modelW,modelH), (0, 0, 0), True, crop=False)
        self.net.setInput(blob)
        outs = self.net.forward(ln)

        diff_time = (datetime.datetime.now() - start).microseconds/1000
        g.logger.debug ('YOLO detection took: {} milliseconds'.format(diff_time))

        class_ids = []
        confidences = []
        boxes = []

        nms_threshold = 0.4
        conf_threshold = 0.2

        # first nms filter out with a yolo confidence of 0.2 (or less)
        if g.config['yolo_min_confidence'] < conf_threshold:
            conf_threshold = g.config['yolo_min_confidence']

        for out in outs:
            for detection in out:
                scores = detection[5:]
                class_id = np.argmax(scores)
                confidence = scores[class_id]
                center_x = int(detection[0] * Width)
                center_y = int(detection[1] * Height)
                w = int(detection[2] * Width)
                h = int(detection[3] * Height)
                x = center_x - w / 2
                y = center_y - h / 2
                class_ids.append(class_id)
                confidences.append(float(confidence))
                boxes.append([x, y, w, h])
              
        start = datetime.datetime.now()
        indices = cv2.dnn.NMSBoxes(boxes, confidences,  conf_threshold, nms_threshold)
        diff_time = (datetime.datetime.now() - start).microseconds/1000
        g.logger.debug ('YOLO NMS filtering took: {} milliseconds'.format(diff_time))

        bbox = []
        label = []
        conf = []

        # now filter out with configured yolo confidence, so we can see rejections in log
        for i in indices:
            i = i[0]
            box = boxes[i]
            x = box[0]
            y = box[1]
            w = box[2]
            h = box[3]
            if confidences[i] >= g.config['yolo_min_confidence']:
                bbox.append( [int(round(x)), int(round(y)), int(round(x + w)), int(round(y + h))])
                label.append(str(self.classes[class_ids[i]]))
                conf.append(confidences[i])
                g.logger.info ('object:{} at {} has a acceptable confidence:{} compared to min confidence of: {}, adding'.format(label[-1], bbox[-1], conf[-1], g.config['yolo_min_confidence']))
            else:
                g.logger.info ('rejecting object:{} at {} because its confidence is :{} compared to min confidence of: {}'.format(str(self.classes[class_ids[i]]), [int(round(x)), int(round(y)), int(round(x + w)), int(round(y + h))], confidences[i], g.config['yolo_min_confidence']))

        
        return bbox, label, conf         


