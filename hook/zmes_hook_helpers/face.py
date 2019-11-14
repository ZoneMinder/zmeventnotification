import numpy as np
import zmes_hook_helpers.common_params as g
import zmes_hook_helpers.log as log
import sys
import os
import cv2
import face_recognition
import pickle
from sklearn import svm

# Class to handle face recognition

class Face:

    def __init__(self, upsample_times=1, num_jitters=0, model='hog'):
        g.logger.debug('Initializing face recognition with model:{} upsample:{}, jitters:{}'
                       .format(model, upsample_times, num_jitters))

        self.upsample_times = upsample_times
        self.num_jitters = num_jitters
        self.model = model
        self.svm_model = None

        encoding_file_name = g.config['known_images_path']+'/faces.svm'
        try:
            if (os.path.isfile(g.config['known_images_path']+'/faces.pickle')):
                # old version, we no longer want it. begone
                g.logger.debug ('removing old faces.pickle. We have moved onto SVMs')
                os.remove (g.config['known_images_path']+'/faces.pickle')
        except Exception as e:
            g.logger.error('Error deleting old pickle file: {}'.format(e))
                

        # to increase performance, read encodings from  file
        if (os.path.isfile(encoding_file_name)):
            g.logger.debug ('pre-trained faces found, using that. If you want to add new images, remove: {}'.format(encoding_file_name))
            with open(encoding_file_name, 'rb') as f:
                self.svm_model  = pickle.load(f)
          
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
                                known_face = face_recognition.load_image_file('{}/{}/{}'.format(directory,entry, person))
                                # Find all the faces and face encodings 
                                # lets NOT use CNN for training. I dont think people will put in 
                                # bad images for training
                                train_model='hog' # change to self.model if you need
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
                        known_face = face_recognition.load_image_file('{}/{}'.format(directory, entry))
                        train_model = 'hog' # change to self.model if you want cnn
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
                self.svm_model = svm.SVC(probability=True, gamma='scale')
                g.logger.debug ('Fitting {}'.format(known_face_names))
                self.svm_model.fit(known_face_encodings, known_face_names)
                f = open(encoding_file_name, "wb")
                pickle.dump(self.svm_model,f)
                f.close()
                g.logger.debug ('wrote encoding file: {}'.format(encoding_file_name))

    def get_classes(self):
        return self.svm_model.classes_

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

        matched_face_names = []
        matched_face_rects = []

        for idx,face_encoding in enumerate(face_encodings):
            preds = self.svm_model.predict_proba([face_encoding])[0]
            best_pred_ndx = np.argmax(preds)
            best_pred = preds[best_pred_ndx]
            loc = face_locations[idx]

            if best_pred >= g.config['face_min_confidence']:
                 matched_face_names.append(self.svm_model.classes_[best_pred_ndx])
                 g.logger.debug('face:{} matched with confidence: {}'.format(self.svm_model.classes_[best_pred_ndx], best_pred))
            else:     
                g.logger.debug ('face confidence is less than {}, marking it unknown'.format(g.config['face_min_confidence']))
                matched_face_names.append(g.config['unknown_face_name'])
                best_pred = 1 # if unknown, don't carry over pred prob
            matched_face_rects.append((loc[3], loc[0], loc[1], loc[2]))
            conf.append(best_pred)
        return matched_face_rects, matched_face_names, conf
