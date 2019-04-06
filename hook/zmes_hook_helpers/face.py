import numpy as np
import zmes_hook_helpers.common_params as g
import zmes_hook_helpers.log as log
import sys
import os
import cv2
import face_recognition


# Class to handle face recognition

class Face:

    def __init__(self, upsample_times=1, num_jitters=0, model='hog'):
        g.logger.debug('Initializing face recognition with model:{} upsample:{}, jitters:{}'
                       .format(model, upsample_times, num_jitters))

        self.upsample_times = upsample_times
        self.num_jitters = num_jitters
        self.model = model
        directory = g.config['known_images_path']
        ext = ['.jpg', '.jpeg', '.png', '.gif']
        self.known_face_encodings = []
        self.known_face_names = []

        try:
            for filename in os.listdir(directory):
                if filename.endswith(tuple(ext)):
                    g.logger.debug('loading face from  {}'.format(filename))
                    known_image = face_recognition.load_image_file('{}/{}'.format(directory, filename))
                    if not len(known_image):
                        g.logger.debug('Skipping {} No faces detected'.format(filename))
                    else:
                        self.known_face_encodings.append(face_recognition.face_encodings(known_image)[0])
                        self.known_face_names.append(os.path.splitext(filename)[0])
        except Exception as e:
            g.logger.error('Error initializing face recognition: {}'.format(e))
            raise ValueError('Error opening known faces directory. Is the path correct?')
        if not len(self.known_face_names):
            g.logger.error('No known faces found to compare')

    def get_classes(self):
        return self.known_face_names

    def _rescale_rects(self, a):
        rects = []
        for (left, top, right, bottom) in a:
            top *= 4
            right *= 4
            bottom *= 4
            left *= 4
            rects.append([left, top, right, bottom])
        return rects

    def detect(self, image):
        labels = []
        classes = []
        conf = []

        # Convert the image from BGR color (which OpenCV uses) to RGB color (which face_recognition uses)
        rgb_image = image[:, :, ::-1]

        # Find all the faces and face encodings 
        face_locations = face_recognition.face_locations(rgb_image, model=self.model, number_of_times_to_upsample=self.upsample_times)
        face_encodings = face_recognition.face_encodings(rgb_image, known_face_locations=face_locations, num_jitters=self.num_jitters)

        matched_face_names = []
        matched_face_rects = []

        for idx, face_encoding in enumerate(face_encodings):
            # See if the face is a match for the known face(s)
            matches = face_recognition.compare_faces(self.known_face_encodings, face_encoding)
            if True in matches:
                first_match_index = matches.index(True)
                name = self.known_face_names[first_match_index]
                matched_face_names.append(name)
                # top right, lower left
            loc = face_locations[idx]
            # convert to left top, right bottom
            matched_face_names.append('unknown')
            matched_face_rects.append((loc[3], loc[0], loc[1], loc[2]))
            conf.append('1')
        #rects = self._rescale_rects(matched_face_rects)
        return matched_face_rects, matched_face_names, conf
