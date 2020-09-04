#!/usr/bin/python3
import re
from configparser import ConfigParser
import sys
import argparse
import os

'''
wej qaStaHvIS wa' ghu'maj. wa'maHlu'chugh, vaj pagh. 
chotlhej'a' qaDanganpu'. chenmoH tlhInganpu'.
'''

def replace_attributes2 (orig, replacements):
    new_string = ''
    for line in orig.splitlines():
        new_line = ''
        for k,v in replacements.items():
            #print ("Replacing "+k+" with "+v)
            line = re.sub(r"(\s|^)({})(\s|^|$|=)".format(k), r"\g<1>{}\g<3>".format(v), line)
            #line = new_line
        new_string = new_string + line + '\n'
    return new_string

def replace_attributes(orig_string, replacements): 
# not used
    def match_attrs(match):
        return replacements[match.group(0)]
    # credit:https://stackoverflow.com/a/17730939
    new_string = (re.sub('|'.join(r'\b%s\b' % re.escape(s) for s in replacements), 
          match_attrs, orig_string) )
    return new_string

def create_attributes(orig_string, new_additions):
    def match_attrs(match):
        return new_additions[match.group(0)]

    new_string = (re.sub('|'.join(r'%s' % re.escape(s) for s in new_additions), 
            match_attrs, orig_string) )
    return new_string


# add new version migrations as functions
# def f_<fromver>_to_<tover>(str):

def f_unknown_to_1_0(str_conf):
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
    s1=replace_attributes2(str_conf,replacements)
    return (create_attributes(s1, new_additions))    

# MAIN

upgrade_path = [
    {'from_version': 'unknown',
     'to_version': '1.0',
     'migrate':f_unknown_to_1_0
    },
   
]

ap = argparse.ArgumentParser(description='objectconfig.ini upgrade script')
ap.add_argument('-c', '--config', help='objectconfig file with path', required=True)
ap.add_argument('-o', '--output', help='output file to write to')


args, u = ap.parse_known_args()
args = vars(args)



config_file = ConfigParser(interpolation=None)
config_file.read(args.get('config'))

version = 'unknown'
if config_file.has_option('general', 'version'):
    version = config_file.get('general', 'version')

print (f'Current version of objectconfig.ini is {version}')
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
        print ('Migrating from {} to {}'.format(u['from_version'],u['to_version']))
        str_conf = u['migrate'](str_conf)
     
    
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
    exit(0)
#from_unknown_to_1_0()
