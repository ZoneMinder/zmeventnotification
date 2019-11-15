import numpy as np
import zmes_hook_helpers.common_params as g
import zmes_hook_helpers.log as log
import sys
import os
import cv2
import face_recognition
import pickle
from sklearn import neighbors
import imutils
import math

# Class to handle face recognition

class Face:

    def __init__(self, upsample_times=1, num_jitters=0, model='hog'):
        g.logger.debug('Initializing face recognition with model:{} upsample:{}, jitters:{}'
                       .format(model, upsample_times, num_jitters))

        self.upsample_times = upsample_times
        self.num_jitters = num_jitters
        self.model = model
        self.knn = None

        encoding_file_name = g.config['known_images_path']+'/faces.dat'
        try:
            if (os.path.isfile(g.config['known_images_path']+'/faces.pickle')):
                # old version, we no longer want it. begone
                g.logger.debug ('removing old faces.pickle, we have moved to clustering')
                os.remove (g.config['known_images_path']+'/faces.pickle')
        except Exception as e:
            g.logger.error('Error deleting old pickle file: {}'.format(e))
                

        # to increase performance, read encodings from  file
        if (os.path.isfile(encoding_file_name)):
            g.logger.debug ('pre-trained faces found, using that. If you want to add new images, remove: {}'.format(encoding_file_name))
            with open(encoding_file_name, 'rb') as f:
                self.knn  = pickle.load(f)
          
            #self.known_face_encodings = data["encodings"]
            #self.known_face_names = data["names"]
        else:
            # no encodings, we have to read and train
            g.logger.debug ('trained file not found, reading from images and doing training...')
            directory = g.config['known_images_path']
            ext = ['.jpg', '.jpeg', '.png', '.gif']
            known_face_encodings = []
            known_face_names = []

            try:
                for entry in os.listdir(directory):
                    if os.path.isdir(directory+'/'+entry):
                    # multiple images for this person,
                    # so we need to iterate that subdir
                        g.logger.debug ('{} is a directory. Processing all images inside it'.format(entry))
                        person_dir = os.listdir(directory+'/'+entry)
                        for person in person_dir:
                            if person.endswith(tuple(ext)):
                                g.logger.debug('loading face from  {}/{}'.format(entry,person))

                                # imread seems to do a better job of color space conversion and orientation
                                known_face = cv2.imread('{}/{}/{}'.format(directory,entry, person))
                                #known_face = face_recognition.load_image_file('{}/{}/{}'.format(directory,entry, person))


                                # Find all the faces and face encodings 
                                # lets NOT use CNN for training. I dont think people will put in 
                                # bad images for training
                                train_model=g.config['face_train_model'] 
                               
                                face_locations = face_recognition.face_locations(known_face, 
                                    model=train_model,number_of_times_to_upsample=self.upsample_times)
                                if len (face_locations) != 1:
                                    g.logger.error ('File {} has multiple faces, cannot use for training. Ignoring...'.format(person))
                                else:
                                    face_encodings = face_recognition.face_encodings(known_face, known_face_locations=face_locations, num_jitters=self.num_jitters)
                                    known_face_encodings.append(face_encodings[0])
                                    known_face_names.append(entry)
                                    #g.logger.debug ('Adding image:{} as known person: {}'.format(person, person_dir))     


                    elif entry.endswith(tuple(ext)):
                    # this was old style. Lets still support it. The image is a single file with no directory
                        g.logger.debug('loading face from  {}'.format(entry))
                        #known_face = cv2.imread('{}/{}/{}'.format(directory,entry, person))
                        known_face = cv2.imread('{}/{}'.format(directory, entry))
                        train_model=g.config['face_train_model']
                        face_locations = face_recognition.face_locations(known_face, model=train_model,
                                  number_of_times_to_upsample=self.upsample_times)
                     
                        if len (face_locations) != 1:
                            g.logger.error ('File {} has multiple faces, cannot use for training. Ignoring...'.format(entry))
                        else:

                            face_encodings = face_recognition.face_encodings(known_face, known_face_locations=face_locations, num_jitters=self.num_jitters)
                            known_face_encodings.append(face_encodings[0])
                            known_face_names.append(os.path.splitext(entry)[0])
                        
            except Exception as e:
                g.logger.error('Error initializing face recognition: {}'.format(e))
                raise ValueError('Error opening known faces directory. Is the path correct?')

            # Now we've finished iterating all files/dirs
            # lets create the svm
            if not len(known_face_names):
                g.logger.error('No known faces found to train, encoding file not created')
            else:
                n_neighbors = int(round(math.sqrt(len(known_face_names))))
                g.logger.debug ('Using n_neighbors to be: {}'.format(n_neighbors))
                self.knn = neighbors.KNeighborsClassifier(n_neighbors=n_neighbors, algorithm=g.config['face_recog_knn_algo'], weights='distance')

                g.logger.debug ('Fitting {}'.format(known_face_names))
                self.knn.fit(known_face_encodings, known_face_names)
             
                

                f = open(encoding_file_name, "wb")
                pickle.dump(self.knn,f)
                f.close()
                g.logger.debug ('wrote encoding file: {}'.format(encoding_file_name))

    def get_classes(self):
        return self.knn.classes_

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
        #rgb_image = image

        # Find all the faces and face encodings in the target image
        face_locations = face_recognition.face_locations(rgb_image, model=self.model, number_of_times_to_upsample=self.upsample_times)
        face_encodings = face_recognition.face_encodings(rgb_image, known_face_locations=face_locations, num_jitters=self.num_jitters)

        if not len(face_encodings):
            return [],[],[]

        # Use the KNN model to find the best matches for the test face
        closest_distances = self.knn.kneighbors(face_encodings, n_neighbors=1)
        are_matches = [closest_distances[0][i][0] <= g.config['face_recog_dist_threshold'] for i in range(len(face_locations))]

        matched_face_names = []
        matched_face_rects = []

        for pred, loc, rec in zip(self.knn.predict(face_encodings), face_locations, are_matches):
            label = pred if rec else g.config['unknown_face_name']
            matched_face_rects.append((loc[3], loc[0], loc[1], loc[2]))
            matched_face_names.append(label)
            conf.append(1)

        return matched_face_rects, matched_face_names, conf
