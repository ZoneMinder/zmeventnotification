# list of variables that are common 
# do not include model specific variables 

ctx = None  # SSL context
logger = None  # logging handler
config = {}  # object that will hold config values
polygons = []  # will contain mask(s) for a monitor

# valid config keys and defaults
config_vals = {
    'version':{
            'section': 'general',
            'default': None,
            'type': 'string',
        },

        'cpu_max_processes':{
            'section': 'general',
            'default': '1',
            'type': 'int',
        },
        'gpu_max_processes':{
            'section': 'general',
            'default': '1',
            'type': 'int',
        },
        'tpu_max_processes':{
            'section': 'general',
            'default': '1',
            'type': 'int',
        },

        'cpu_max_lock_wait':{
            'section': 'general',
            'default': '120',
            'type': 'int',
        },

        'gpu_max_lock_wait':{
            'section': 'general',
            'default': '120',
            'type': 'int',
        },
        'tpu_max_lock_wait':{
            'section': 'general',
            'default': '120',
            'type': 'int',
        },


        
        'secrets':{
            'section': 'general',
            'default': None,
            'type': 'string',
        },
         'base_data_path': {
            'section': 'general',
            'default': '/var/lib/zmeventnotification',
            'type': 'string'
        },
        'pyzm_overrides': {
            'section': 'general',
            'default': "{}",
            'type': 'dict',

        },
        'portal':{
            'section': 'general',
            'default': '',
            'type': 'string',
        },
        'api_portal':{
            'section': 'general',
            'default': '',
            'type': 'string',
        },
        'user':{
            'section': 'general',
            'default': None,
            'type': 'string'
        },
        'password':{
            'section': 'general',
            'default': None,
            'type': 'string'
        },
        'basic_user':{
            'section': 'general',
            'default': None,
            'type': 'string'
        },
     
        'basic_password':{
            'section': 'general',
            'default': None,
            'type': 'string'
        },
        'image_path':{
            'section': 'general',
            'default': '/var/lib/zmeventnotification/images',
            'type': 'string'
        },
        
        'match_past_detections':{
            'section': 'general',
            'default': 'no',
            'type': 'string'
        },
        'past_det_max_diff_area':{
            'section': 'general',
            'default': '5%',
            'type': 'string'
        },
        'max_detection_size':{
            'section': 'general',
            'default': '',
            'type': 'string'
        },
        'frame_id':{
            'section': 'general',
            'default': 'snapshot',
            'type': 'string'
        },
        'bestmatch_order': {
            'section':'general',
            'default': 'a,s',
            'type':'string',
        },
        'wait': {
            'section': 'general',
            'default':'0',
            'type': 'int'
        },

        'resize':{
            'section': 'general',
            'default': 'no',
            'type': 'string'
        },
        'delete_after_analyze':{
            'section': 'general',
            'default': 'no',
            'type': 'string',
        },
        'show_percent':{
            'section': 'general',
            'default': 'no',
            'type': 'string'
        },
        'allow_self_signed':{
            'section': 'general',
            'default': 'yes',
            'type': 'string'
        },
        'write_image_to_zm':{
            'section': 'general',
            'default': 'yes',
            'type': 'string'
        },
        'write_debug_image':{
            'section': 'general',
            'default': 'yes',
            'type': 'string'
        },
        'detection_sequence':{
            'section': 'general',
            'default': 'object',
            'type': 'str_split'
        },
        'detection_mode': {
            'section':'general',
            'default':'all',
            'type':'string'
        },
        'import_zm_zones':{
            'section': 'general',
            'default': 'no',
            'type': 'string',
        },
        'only_triggered_zm_zones':{
            'section': 'general',
            'default': 'no',
            'type': 'string',
        },
        'poly_color':{
            'section': 'general',
            'default': '(127,140,141)',
            'type': 'eval'
        },
        'poly_thickness':{
            'section': 'general',
            'default': '2',
            'type': 'int'
        },

        # animation for push

        'create_animation':{
            'section': 'animation',
            'default': 'no',
            'type': 'string'
        },
        'animation_types':{
            'section': 'animation',
            'default': 'mp4',
            'type': 'string'
        },
        'animation_width':{
            'section': 'animation',
            'default': '400',
            'type': 'int'
        },
        'animation_retry_sleep':{
            'section': 'animation',
            'default': '15',
            'type': 'int'
        },
        'animation_max_tries':{
            'section': 'animation',
            'default': '3',
            'type': 'int'
        },
        'fast_gif':{
            'section': 'animation',
            'default': 'no',
            'type': 'string'
        },

        # remote ML
     

        'ml_gateway': {
            'section': 'remote',
            'default': None,
            'type': 'string'
        },

        'ml_fallback_local': {
            'section': 'remote',
            'default': 'no',
            'type': 'string'
        },
       
        'ml_user': {
            'section': 'remote',
            'default': None,
            'type': 'string'
        },
        'ml_password': {
            'section': 'remote',
            'default': None,
            'type': 'string'
        },

        'disable_locks': {
            'section': 'ml',
            'default': 'no',
            'type': 'string'
        },
        'use_sequence': {
            'section': 'ml',
            'default': 'yes',
            'type': 'string'
        },
        'ml_sequence': {
            'section': 'ml',
            'default': None,
            'type': 'string'
        },
        'stream_sequence': {
            'section': 'ml',
            'default': None,
            'type': 'string'
        },
     
     
       
       'object_detection_pattern':{
            'section': 'object',
            'default': '.*',
            'type': 'string'
        },
       
       'object_framework':{
            'section': 'object',
            'default': 'opencv',
            'type': 'string'
        },
        'object_processor':{
            'section': 'object',
            'default': 'cpu',
            'type': 'string'
        },
        'object_config':{
            'section': 'object',
            'default': '/var/lib/zmeventnotification/models/yolov3/yolov3.cfg',
            'type': 'string'
        },
        'object_weights':{
            'section': 'object',
            'default': '/var/lib/zmeventnotification/models/yolov3/yolov3.weights',
            'type': 'string'
        },
        'object_labels':{
            'section': 'object',
            'default': '/var/lib/zmeventnotification/models/yolov3/coco.names',
            'type': 'string'
        },
       

        'object_min_confidence': {
            'section': 'object',
            'default': '0.4',
            'type': 'float'
        },
        
       # Face
       'face_detection_pattern':{
            'section': 'face',
            'default': '.*',
            'type': 'string'
        },
        'face_detection_framework':{
            'section': 'face',
            'default': 'dlib',
            'type': 'string'
        },
        'face_recognition_framework':{
            'section': 'face',
            'default': 'dlib',
            'type': 'string'
        },
        'face_processor': {
            'section' : 'face',
            'default' : 'cpu',
            'type'    : 'string'
        },
        'face_num_jitters':{
            'section': 'face',
            'default': '0',
            'type': 'int',
        },
        'face_upsample_times':{
            'section': 'face',
            'default': '1',
            'type': 'int',
        },
        'face_model':{
            'section': 'face',
            'default': 'hog',
            'type': 'string',
        },
        'face_train_model':{
            'section': 'face',
            'default': 'hog',
            'type': 'string',
        },
         'face_recog_dist_threshold': {
            'section': 'face',
            'default': '0.6',
            'type': 'float'
        },
        'face_recog_knn_algo': {
            'section': 'face',
            'default': 'ball_tree',
            'type': 'string'
        },
        'known_images_path':{
            'section': 'face',
            'default': '/var/lib/zmeventnotification/known_faces',
            'type': 'string',
        },
        'unknown_images_path':{
            'section': 'face',
            'default': '/var/lib/zmeventnotification/unknown_faces',
            'type': 'string',
        },
        'unknown_face_name':{
            'section': 'face',
            'default': 'unknown face',
            'type': 'string',
        },
        'save_unknown_faces':{
            'section': 'face',
            'default': 'yes',
            'type': 'string',
        },

        'save_unknown_faces_leeway_pixels':{
            'section': 'face',
            'default': '50',
            'type': 'int',
        },

        # generic ALPR
        'alpr_service': {
            'section': 'alpr',
            'default': 'plate_recognizer',
            'type': 'string',
        },
        'alpr_detection_pattern':{
            'section': 'alpr',
            'default': '.*',
            'type': 'string'
        },
        'alpr_url': {
            'section': 'alpr',
            'default': None,
            'type': 'string',
        },
        'alpr_key': {
            'section': 'alpr',
            'default': '',
            'type': 'string',
        },
        'alpr_use_after_detection_only': {
            'section': 'alpr',
            'type': 'string',
            'default': 'yes',
        },
        'alpr_api_type':{
            'section': 'alpr',
            'default': 'cloud',
            'type': 'string'
        },

        # Plate recognition specific
        'platerec_stats':{
            'section': 'alpr',
            'default': 'no',
            'type': 'string'
        },

        'platerec_payload':{
            'section': 'alpr',
            'default': None,
            'type': 'eval'
        },
        'platerec_config':{
            'section': 'alpr',
            'default': None,
            'type': 'eval'
        },

       
        'platerec_regions':{
            'section': 'alpr',
            'default': None,
            'type': 'eval'
        },
        'platerec_min_dscore':{
            'section': 'alpr',
            'default': '0.3',
            'type': 'float'
        },
       
        'platerec_min_score':{
            'section': 'alpr',
            'default': '0.5',
            'type': 'float'
        },

        # OpenALPR specific
        'openalpr_recognize_vehicle':{
            'section': 'alpr',
            'default': '0',
            'type': 'int'
        },
        'openalpr_country':{
            'section': 'alpr',
            'default': 'us',
            'type': 'string'
        },
        'openalpr_state':{
            'section': 'alpr',
            'default': None,
            'type': 'string'
        },

        'openalpr_min_confidence': {
            'section': 'alpr',
            'default': '0.3',
            'type': 'float'
        },

        # OpenALPR command line specfic

         'openalpr_cmdline_binary':{
            'section': 'alpr',
            'default': 'alpr',
            'type': 'string'
        },
        
         'openalpr_cmdline_params':{
            'section': 'alpr',
            'default': '-j',
            'type': 'string'
        },
        'openalpr_cmdline_min_confidence': {
            'section': 'alpr',
            'default': '0.3',
            'type': 'float'
        },
       

    }
