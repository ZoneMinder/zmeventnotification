#!/usr/bin/python3
import re
from configparser import ConfigParser
import sys
import argparse
import os
import re
'''
wej qaStaHvIS wa' ghu'maj. wa'maHlu'chugh, vaj pagh. 
chotlhej'a' qaDanganpu'. chenmoH tlhInganpu'.
'''

breaking = False

def sanity_check(s, c, v):

    for attr in s:
        print ('Doing a sanity check, {} should not be there...'.format(attr))
        #if attr in c:
        if re.search(f'(^| |\t|\n){attr}(=| |\t)',c):
            print  (
            '''
There is an error in your config. While upgrading to version:{} 
I found a key ({}) that should not have been there. 
This usually means when you last upgraded, your version attribute
was not upgraded for some reason. To be safe, this script will not
upgrade the script till you fix the potential issues (or manually 
bump up version)
            '''.format(v,attr))
            exit(1)        

    print ('Sanity check passed!')
    return True

def replace_attributes (orig, replacements):
    new_string = ''
    for line in orig.splitlines():
        new_line = ''
        for k,v in replacements.items():
            #print ("Replacing "+k+" with "+v)
            line = re.sub(r"(\s|^)({})(\s|^|$|=)".format(k), r"\g<1>{}\g<3>".format(v), line)
            #line = new_line
        new_string = new_string + line + '\n'
    return new_string


def create_attributes(orig_string, new_additions):
    def match_attrs(match):
        return new_additions[match.group(0)]

    new_string = (re.sub('|'.join(r'%s' % re.escape(s) for s in new_additions), 
            match_attrs, orig_string) )
    return new_string


# add new version migrations as functions
# def f_<fromver>_to_<tover>(str_conf,new_version):

def f_1_1_to_1_2(str_conf,new_version):

    print ('*** Only basic changes have been made. Please study the sample objectconfig.ini file to see all the other parameters ***')

    should_not_be_there = {
        'ml_sequence',
        'stream_sequence'
    }
    replacements = {
        'version=1.1': 'version='+new_version,
        '# config for object': ''
    }
    new_additions= {
'\n[object]\n':
'''
[ml]

# NEW: If enabled (default = no), we will use ml_sequence and stream_sequence 
# and ignore everything in [object] [face] and [alpr]
#
# use_sequence = yes

# NEW: You can use this structure to create a chain of detection algorithms
# See https://pyzm.readthedocs.io/en/latest/source/pyzm.html#detectsequence for options (look at options field)

# VERY IMPORTANT - The curly braces need to be indented to be inside ml_sequence
# tag, or parsing will fail
# NOTE: If you specify this attribute, all settings in [object], [face] and [alpr] will be ignored

ml_sequence= {
            'general': {
                    'model_sequence': 'object,face,alpr',

            },
            'object': {
                    'general':{
                            'pattern':'(person)',
                            'same_model_sequence_strategy': 'first' # also 'most', 'most_unique's
                    },
                    'sequence': [{
                            #First run on TPU with higher confidence
                            'object_weights':'{{base_data_path}}/models/coral_edgetpu/ssd_mobilenet_v2_coco_quant_postprocess_edgetpu.tflite',
                            'object_labels': '{{base_data_path}}/models/coral_edgetpu/coco_indexed.names',
                            'object_min_confidence': 0.6,
                            'object_framework':'coral_edgetpu'
                    },
                    {
                            # YoloV4 on GPU if TPU fails (because sequence strategy is 'first')
                            'object_config':'{{base_data_path}}/models/yolov4/yolov4.cfg',
                            'object_weights':'{{base_data_path}}/models/yolov4/yolov4.weights',
                            'object_labels': '{{base_data_path}}/models/yolov4/coco.names',
                            'object_min_confidence': 0.3,
                            'object_framework':'opencv',
                            'object_processor': 'gpu'
                    }]
            },
            'face': {
                    'general':{
                            'pattern': '.*',
                            'same_model_sequence_strategy': 'first'
                    },
                    'sequence': [{
                            'face_detection_framework': 'dlib',
                            'known_images_path': '{{base_data_path}}/known_faces',
                            'face_model': 'cnn',
                            'face_train_model': 'cnn',
                            'face_recog_dist_threshold': 0.6,
                            'face_num_jitters': 1,
                            'face_upsample_times':1,
                            'save_unknown_faces':'yes',
                            'save_unknown_faces_leeway_pixels':100
                    }]
            },

            'alpr': {
                    'general':{
                            'same_model_sequence_strategy': 'first',
                            'pre_existing_labels':['car', 'motorbike', 'bus', 'truck', 'boat'],

                    },
                    'sequence': [{
                            'alpr_api_type': 'cloud',
                            'alpr_service': 'plate_recognizer',
                            'alpr_key': '!PLATEREC_ALPR_KEY',
                            'platrec_stats': 'no',
                            'platerec_min_dscore': 0.1,
                            'platerec_min_score': 0.2,
                    }]
            }
        }

# NEW: This new structure can be used to select arbitrary frames for analysis 
# See https://pyzm.readthedocs.io/en/latest/source/pyzm.html#pyzm.ml.detect_sequence.DetectSequence.detect_stream
# for options (look at options field)
# NOTE: If stream_sequence specified, the following pre-existing attributes in objectconfig.ini will be ignored
# as you are now able to specify them inside the sequence:
#   - frame_id (replaced by frame_set inside stream_sequence),
#   - resize 
#   - delete_after_analyze 
#   
stream_sequence = {
        'detection_mode': 'most_models',
        'frame_set': 'snapshot,alarm',

    }

# config for object
[object]
''' 
  
        
    }
    if sanity_check(should_not_be_there, str_conf, new_version):
        s1=replace_attributes(str_conf,replacements)
        return (create_attributes(s1, new_additions))        


def f_1_0_to_1_1(str_conf,new_version):
    replacements = {
        'version=1.0': 'version='+new_version
    }
    new_additions = {
'\n[animation]\n':
'''
#NEW: if animation_types is gif then when can generate a fast preview gif
# every second frame is skipped and the frame rate doubled
# to give quick preview, Default (no)
fast_gif=no
'''

    }
    should_not_be_there = {
        'fast_gif'
    }

    if sanity_check(should_not_be_there, str_conf, new_version):
        s1=replace_attributes(str_conf,replacements)
        return (create_attributes(s1, new_additions))    
        



def f_unknown_to_1_0(str_conf, new_version):
    global breaking
    breaking = True
    should_not_be_there = {
        'cpu_max_processes',
        'tpu_max_processes',
        'gpu_max_processes',
        'cpu_max_lock_wait',
        'tpu_max_lock_wait',
        'gpu_max_lock_wait',
        'object_framework',
        'object_processor',
        'face_detection_framework',
        'face_recognition_framework'


    }

    replacements = {
    'models':'detection_sequence',
    '[yolo]': '[object]',
    'yolo': 'object',
    'yolo_min_confidence': 'object_min_confidence',
    '[ml]': '[remote]',
    'config': 'object_config',
    'weights': 'object_weights',
    'labels': 'object_labels',
    'tiny_config': '#REMOVE tiny_config',
    'tiny_weights': '#REMOVE tiny_weights',
    'tiny_labels': '#REMOVE tiny_labels',
    'yolo_type': '#REMOVE yolo_type',
    'alpr_pattern': 'alpr_detection_pattern',
    'detect_pattern': 'object_detection_pattern'
    }

    new_additions={
'\n[general]\n':
'''
[general]
# Please don't change this. It is used by the config upgrade script
version=1.0

# NEW: You can now limit the # of detection process
# per target processor. If not specified, default is 1
# Other detection processes will wait to acquire lock

cpu_max_processes=3
tpu_max_processes=1
gpu_max_processes=1

# NEW: Time to wait in seconds per processor to be free, before
# erroring out. Default is 120 (2 mins)
cpu_max_lock_wait=120
tpu_max_lock_wait=120
gpu_max_lock_wait=120

''',
'\n[alpr]\n': 
'''
[alpr]

#NEW: You can specify a license plate matching pattern here
alpr_detection_pattern=.*
''',

'\n[object]\n': 
''' 
[object]

#NEW: opencv or coral_edgetpu
#object_framework=opencv

#NEW: CPU or GPU
#object_processor=cpu #or gpu
''',

'\n[face]\n': 
''' 
[face]

# NEW: You can specify a face matching pattern here
face_detection_pattern=.*
#face_detection_pattern=(King|Kong)

# As of today, only dlib can be used
# Coral TPU only supports face detection
# Maybe in future, we can do different frameworks
# for detection and recognition

face_detection_framework=dlib
face_recognition_framework=dlib
''',

    }

    if sanity_check(should_not_be_there, str_conf, new_version):
        s1=replace_attributes(str_conf,replacements)
        return (create_attributes(s1, new_additions))    

# MAIN

upgrade_path = [
    {'from_version': 'unknown',
     'to_version': '1.0',
     'migrate':f_unknown_to_1_0
    },
    {'from_version': '1.0',
     'to_version': '1.1',
     'migrate':f_1_0_to_1_1
    },
     {'from_version': '1.1',
     'to_version': '1.2',
     'migrate':f_1_1_to_1_2
    },
   
]

ap = argparse.ArgumentParser(description='objectconfig.ini upgrade script')
ap.add_argument('-c', '--config', help='objectconfig file with path', required=True)
ap.add_argument('-o', '--output', help='output file to write to')


args, u = ap.parse_known_args()
args = vars(args)



config_file = ConfigParser(interpolation=None, inline_comment_prefixes='#')
config_file.read(args.get('config'))

version = 'unknown'
if config_file.has_option('general', 'version'):
    version = config_file.get('general', 'version')

print ('Current version of file is {}'.format(version))
f=open(args.get('config'))
str_conf = f.read()
f.close()

for i,u in enumerate(upgrade_path):
    if u['from_version'] == version:
        break
else:
    i = -1

if i >=0:
    for u in upgrade_path[i:]:
        print ('-------------------------------------------------')
        print ('Migrating from {} to {}\n'.format(u['from_version'],u['to_version']))
        str_conf = u['migrate'](str_conf, u['to_version'])
     
    
    out_file = args.get('output') if args.get('output')  else 'migrated-'+os.path.basename(args.get('config'))
    f = open ( out_file,'w')
    f.write(str_conf)
    f.close()
    print ('''

----------------------| NOTE |-------------------------
The migration is best effort. May contain errors.
Please review the modified file.
Items commented out with #REMOVE can be deleted.
Items marked with #NEW are new options to customize.

    ''')

    print ('Migrated config written to: {}'.format(out_file))
else:
    print ('Nothing to migrate')

if breaking:
    print("\nTHIS IS A BREAKING CHANGE RELEASE. THINGS WILL NOT WORK TILL YOU FOLLOW https://zmeventnotification.readthedocs.io/en/latest/guides/breaking.html#version-5-16-0-onwards\n")
    
exit(0)
#from_unknown_to_1_0()
