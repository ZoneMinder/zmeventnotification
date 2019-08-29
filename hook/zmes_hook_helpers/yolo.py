import numpy as np
import zmes_hook_helpers.common_params as g
import zmes_hook_helpers.log as log
import sys
import cv2

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
        scale = 0.00392
        if g.config['yolo_type'] == 'tiny':
            config_file_abs_path = g.config['tiny_config']
            weights_file_abs_path = g.config['tiny_weights']
        else:
            config_file_abs_path = g.config['config']
            weights_file_abs_path = g.config['weights']

        if self.initialize:
            self.populate_class_labels()
            self.net = cv2.dnn.readNet(weights_file_abs_path, config_file_abs_path)
            self.initialize = False
            g.logger.debug('Initializing Yolo')
            g.logger.debug('config:{}, weights:{}'.format(config_file_abs_path, weights_file_abs_path))

        blob = cv2.dnn.blobFromImage(image, scale, (416, 416), (0, 0, 0), True, crop=False)
        self.net.setInput(blob)
        outs = self.net.forward(self.get_output_layers())

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
            bbox.append( [int(round(x)), int(round(y)), int(round(x + w)), int(round(y + h))])
            label.append(str(self.classes[class_ids[i]]))
            conf.append(confidences[i])
        return bbox, label, conf                                   

