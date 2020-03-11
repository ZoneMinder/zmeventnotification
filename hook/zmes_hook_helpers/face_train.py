import face_recognition
import cv2
import argparse
import pickle
from sklearn import neighbors
import imutils
import math
import ssl
import os
import datetime

import zmes_hook_helpers.log as log
import zmes_hook_helpers.common_params as g
import zmes_hook_helpers.utils as utils

start = datetime.datetime.now()
diff_time = (datetime.datetime.now() - start).microseconds / 1000
g.logger.debug(
    'Face Recognition library load time took: {} milliseconds'.format(
        diff_time))


def train():
    start = datetime.datetime.now()
    known_images_path = g.config['known_images_path']
    train_model = g.config['face_train_model']
    knn_algo = g.config['face_recog_knn_algo']
    upsample_times = g.config['face_upsample_times']
    num_jitters = g.config['face_num_jitters']

    encoding_file_name = known_images_path + '/faces.dat'
    try:
        if (os.path.isfile(known_images_path + '/faces.pickle')):
            # old version, we no longer want it. begone
            g.logger.debug(
                'removing old faces.pickle, we have moved to clustering')
            os.remove(known_images_path + '/faces.pickle')
    except Exception as e:
        g.logger.error('Error deleting old pickle file: {}'.format(e))

    directory = known_images_path
    ext = ['.jpg', '.jpeg', '.png', '.gif']
    known_face_encodings = []
    known_face_names = []

    try:
        for entry in os.listdir(directory):
            if os.path.isdir(directory + '/' + entry):
                # multiple images for this person,
                # so we need to iterate that subdir
                g.logger.debug(
                    '{} is a directory. Processing all images inside it'.
                    format(entry))
                person_dir = os.listdir(directory + '/' + entry)
                for person in person_dir:
                    if person.endswith(tuple(ext)):
                        g.logger.debug('loading face from  {}/{}'.format(
                            entry, person))

                        # imread seems to do a better job of color space conversion and orientation
                        known_face = cv2.imread('{}/{}/{}'.format(
                            directory, entry, person))
                        if known_face is None or known_face.size == 0:
                            g.logger.error('Error reading file, skipping')
                            continue
                        #known_face = face_recognition.load_image_file('{}/{}/{}'.format(directory,entry, person))

                        face_locations = face_recognition.face_locations(
                            known_face,
                            model=train_model,
                            number_of_times_to_upsample=upsample_times)
                        if len(face_locations) != 1:
                            g.logger.error(
                                'File {} has {} faces, cannot use for training. We need exactly 1 face. If you think you have only 1 face try using "cnn" for training mode. Ignoring...'
                                .format(person), len(face_locations))
                        else:
                            face_encodings = face_recognition.face_encodings(
                                known_face,
                                known_face_locations=face_locations,
                                num_jitters=num_jitters)
                            known_face_encodings.append(face_encodings[0])
                            known_face_names.append(entry)
                            #g.logger.debug ('Adding image:{} as known person: {}'.format(person, person_dir))

            elif entry.endswith(tuple(ext)):
                # this was old style. Lets still support it. The image is a single file with no directory
                g.logger.debug('loading face from  {}'.format(entry))
                #known_face = cv2.imread('{}/{}/{}'.format(directory,entry, person))
                known_face = cv2.imread('{}/{}'.format(directory, entry))
                face_locations = face_recognition.face_locations(
                    known_face,
                    model=train_model,
                    number_of_times_to_upsample=upsample_times)

                if len(face_locations) != 1:
                    g.logger.error(
                                'File {} has {} faces, cannot use for training. We need exactly 1 face. If you think you have only 1 face try using "cnn" for training mode. Ignoring...'
                                .format(person), len(face_locations))
                else:
                    face_encodings = face_recognition.face_encodings(
                        known_face,
                        known_face_locations=face_locations,
                        num_jitters=num_jitters)
                    known_face_encodings.append(face_encodings[0])
                    known_face_names.append(os.path.splitext(entry)[0])

    except Exception as e:
        g.logger.error('Error initializing face recognition: {}'.format(e))
        raise ValueError(
            'Error opening known faces directory. Is the path correct?')

    # Now we've finished iterating all files/dirs
    # lets create the svm
    if not len(known_face_names):
        g.logger.error(
            'No known faces found to train, encoding file not created')
    else:
        n_neighbors = int(round(math.sqrt(len(known_face_names))))
        g.logger.debug('Using n_neighbors to be: {}'.format(n_neighbors))
        knn = neighbors.KNeighborsClassifier(n_neighbors=n_neighbors,
                                             algorithm=knn_algo,
                                             weights='distance')

        g.logger.debug('Training model ...')
        knn.fit(known_face_encodings, known_face_names)

        f = open(encoding_file_name, "wb")
        pickle.dump(knn, f)
        f.close()
        g.logger.debug('wrote encoding file: {}'.format(encoding_file_name))
    diff_time = (datetime.datetime.now() - start).microseconds / 1000
    g.logger.debug(
        'Face Recognition training took: {} milliseconds'.format(diff_time))
