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
            'default': {},
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
        'wait': {
            'section': 'general',
            'default':'0',
            'type': 'int'
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
        'ml_sequence': {
            'section': 'ml',
            'default': None,
            'type': 'dict'
        },
        'stream_sequence': {
            'section': 'ml',
            'default': None,
            'type': 'dict'
        },
     
     
       
    }
