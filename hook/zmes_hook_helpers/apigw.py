import zmes_hook_helpers.common_params as g
import zmes_hook_helpers.log as log
import sys


class YoloRemote:
    def __init__(self):
        if g.config['yolo_type'] == 'tiny':
            class_file_abs_path = g.config['tiny_labels']
        else:
            class_file_abs_path = g.config['labels']
        f = open(class_file_abs_path, 'r')
        self.classes = [line.strip() for line in f.readlines()]

    def set_classes(self, classes):
        self.classes = classes

    def get_classes(self):
        return self.classes


class FaceRemote:
    def __init__(self):
        self.classes = []

    def set_classes(self, classes):
        self.classes = classes

    def get_classes(self):
        return self.classes
