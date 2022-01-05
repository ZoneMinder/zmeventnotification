#!/usr/bin/python3
import copy
import glob
import json
import os
import signal
import subprocess
import sys
import time
import urllib.parse
from argparse import ArgumentParser
from ast import literal_eval
from configparser import ConfigParser
from datetime import datetime
from functools import partial
from io import BytesIO
from pathlib import Path
from re import findall
from threading import Thread
from traceback import format_exc
from typing import Optional, Union

import cv2
# Pycharm hack for intellisense
# from cv2 import cv2
from sqlalchemy import create_engine, MetaData, Table, select
from sqlalchemy.engine import ResultProxy
from sqlalchemy.exc import SQLAlchemyError
import numpy as np
import requests
import urllib3
# BytesIO and Image for saving images to bytes buffer
from PIL import Image
from yaml import safe_load

import pyzm.helpers.new_yaml
import pyzm.helpers.pyzm_utils
from pyzm.interface import GlobalConfig
from pyzm import __version__ as pyzm_version
from pyzm.helpers.new_yaml import create_api, start_logs
from pyzm.helpers.pyzm_utils import (
    resize_image,
    write_text,
    pretty_print,
    draw_bbox,
    verify_vals,
    grab_frameid,
    str2bool,
    do_mqtt,
    do_hass
)

lp: str = 'zmes:'
__app_version__: str = "0.0.2"
DEFAULT_CONFIG: dict = safe_load('''
    custom_push: no
    custom_push_script: ''
    force_mpd: no
    same_model_high_conf: no
    skip_mons: 
    force_live: no
    sanitize_logs: no
    sanitize_str: <sanitized>
    show_models: no
    save_image_train: no
    save_image_train_dir: '/var/lib/zmeventnotification/images'
    force_debug: no
    frame_set: snapshot,alarm,snapshot
    cpu_max_processes: 2
    gpu_max_processes: 2
    tpu_max_processes: 2
    cpu_max_lock_wait: 120
    gpu_max_lock_wait: 120
    tpu_max_lock_wait: 120
    pyzm_overrides: '{ "log_level_debug" : 5 }'
    secrets: ''
    user: ''
    password: ''
    basic_user: ''
    basic_password: ''
    portal: ''
    api_portal: ''
    image_path: '/var/lib/zmeventnotification/images'
    allow_self_signed: yes
    match_past_detections: no
    past_det_max_diff_area: '5%'
    max_detection_size: ''
    contained_area: 1px
    model_sequence: 'object,face,alpr'
    base_data_path: '/var/lib/zmeventnotification'
    resize: no
    picture_timestamp:
      enabled: no
      date format: '%Y-%m-%d %H:%M:%S'
      monitor id: yes
      text color: (255,255,255)
      background: yes
      bg color: (0,0,0)

    delete_after_analyze: yes
    write_debug_image: no
    write_image_to_zm: yes
    show_percent: yes
    draw_poly_zone: yes
    contained_area: 1px
    poly_color: (0,0,255)
    poly_thickness: 2
    import_zm_zones: no
    only_triggered_zm_zones: no
    show_filtered_detections: no
    show_conf_filtered: no

    hass_enabled: no
    hass_server: ''
    hass_token: ''

    hass_people: {}
    hass_notify: ''
    hass_cooldown: ''

    push_enable: no
    push_force: no
    push_token: ''
    push_key: ''

    push_url: no
    push_user: ''
    push_pass: ''

    push_errors: no
    push_err_token: ''
    push_err_key: ''
    push_err_device: ''

    push_jpg: ''
    push_jpg_key: ''
    push_gif: ''
    push_gif_key: ''

    push_debug_device: '' 
    push_cooldown: ''

    mqtt_enable: no
    mqtt_force: no
    mqtt_topic: ''
    mqtt_broker: ''
    mqtt_port: '' 
    mqtt_user: ''
    mqtt_pass: ''
    mqtt_tls_allow_self_signed: no
    mqtt_tls_insecure: no
    tls_ca: ''
    tls_cert: ''
    tls_key: ''

    create_animation: no
    animation_timestamp:
      enabled: no
      date format: '%Y-%m-%d %H:%M:%S'
      monitor id: yes
      text color: (255,255,255)
      background: yes
      bg color: (0,0,0)
    animation_types: 'gif,mp4'
    fast_gif: no
    animation_width: 640
    animation_retry_sleep: 3
    animation_max_tries: 8

    ml_fallback_local: no
    ml_enable: no
    ml_routes: []

    object_detection_pattern: '(person|car|motorbike|bus|truck|boat|dog|cat)'
    object_min_confidence: 0.6
    tpu_object_labels: '/var/lib/zmeventnotification/models/coral_edgetpu/coco_indexed.names'
    tpu_object_framework: coral_edgetpu
    tpu_object_processor: tpu
    tpu_min_confidence: 0.6

    yolo4_object_weights: '/var/lib/zmeventnotification/models/yolov4/yolov4.weights'
    yolo4_object_labels: '/var/lib/zmeventnotification/models/yolov4/coco.names'
    yolo4_object_config: '/var/lib/zmeventnotification/models/yolov4/yolov4.cfg'
    yolo4_object_framework: opencv
    yolo4_object_processor: gpu
    fp16_target: no

    yolo3_object_weights: '/var/lib/zmeventnotification/models/yolov3/yolov3.weights'
    yolo3_object_labels: '/var/lib/zmeventnotification/models/yolov3/coco.names'
    yolo3_object_config: '/var/lib/zmeventnotification/models/yolov3/yolov3.cfg'
    yolo3_object_framework: opencv
    yolo3_object_processor: gpu

    tinyyolo_object_config: '/var/lib/zmeventnotification/models/tinyyolov4/yolov4-tiny.cfg'
    tinyyolo_object_weights: '/var/lib/zmeventnotification/models/tinyyolov4/yolov4-tiny.weights'
    tinyyolo_object_labels: '/var/lib/zmeventnotification/models/tinyyolov4/coco.names'
    tinyyolo_object_framework: opencv
    tinyyolo_object_processor: gpu

    face_detection_pattern: .*
    known_images_path: '/var/lib/zmeventnotification/known_faces'
    unknown_images_path: '/var/lib/zmeventnotification/unknown_faces'
    save_unknown_faces: no
    save_unknown_faces_leeway_pixels: 100
    face_detection_framework: dlib
    face_dlib_processor: gpu
    face_num_jitters: 1
    face_model: cnn
    face_upsample_times: 1
    face_recog_dist_threshold: 0.6
    face_train_model: cnn
    unknown_face_name: Unknown

    alpr_detection_pattern: .*
    alpr_api_type: ''
    alpr_service: ''
    alpr_url: ''
    alpr_key: ''
    platerec_stats: no
    platerec_regions: []
    platerec_min_dscore: 0.1
    platerec_min_score: 0.2

    openalpr_recognize_vehicle: 0
    openalpr_country: '' 
    openalpr_state: ''
    openalpr_min_confidence: 0.3

    openalpr_cmdline_binary: alpr
    openalpr_cmdline_params: -j -d
    openalpr_cmdline_min_confidence: 0.3

    smart_fs_thresh :  5
    disable_locks :  no
    frame_strategy :  first
    same_model_sequence_strategy :  most

    stream_sequence :
      frame_strategy: '{{frame_strategy}}'
      frame_set: '{{frame_set}}'
      contig_frames_before_error: 2
      max_attempts: 3
      sleep_between_attempts: 2.23
      sleep_between_frames: 0
      sleep_between_snapshots: 1.5
      smart_fs_thresh: '5'

    ml_sequence:
      general:
        model_sequence: '{{model_sequence}}'
        disable_locks: no

      object:
        general:
          object_detection_pattern: '(person|dog|cat|car|truck)'
          same_model_sequence_strategy: '{{same_model_sequence_strategy}}'
          contained_area: '1px'
        sequence:
        - name: 'Yolo v4'
        enabled: 'yes'
        object_config: '{{yolo4_object_config}}'
        object_weights: '{{yolo4_object_weights}}'
        object_labels: '{{yolo4_object_labels}}'
        object_min_confidence: '{{object_min_confidence}}'
        object_framework: '{{yolo4_object_framework}}'
        object_processor: '{{yolo4_object_processor}}'
        gpu_max_processes: '{{gpu_max_processes}}'
        gpu_max_lock_wait: '{{gpu_max_lock_wait}}'
        cpu_max_processes: '{{cpu_max_processes}}'
        cpu_max_lock_wait: '{{cpu_max_lock_wait}}'
        fp16_target: '{{fp16_target}}'  # only applies to GPU, default is 'no'

      alpr:
        general:
          same_model_sequence_strategy: 'first'
          alpr_detection_pattern: '{{alpr_detection_pattern}}'

        sequence: []

      face:
        general:
          face_detection_pattern: '{{face_detection_pattern}}'
          same_model_sequence_strategy: 'union'

          sequence: []
    ''')
g: GlobalConfig


def _get_jwt_filename(ml_api_url):
    _file_name = ml_api_url.lstrip('http://').lstrip('https://')
    # If there is a :port
    _file_name = _file_name.split(':')
    if len(_file_name) > 1:
        _file_name = _file_name[0]
    return _file_name

def remote_login(user, password, ml_api_url: str):
    access_token: Optional[str] = None
    lp = "zmes:mlapi:login:"
    ml_login_url = f"{ml_api_url}/login"
    _file_name = _get_jwt_filename(ml_api_url)
    # todo: add to a cron cleanup job or something
    jwt_file = f"{g.config['base_data_path']}/{_file_name}_login.json"  # mlapi access_token
    if Path(jwt_file).is_file():
        try:
            with open(jwt_file) as json_file:
                data = json.load(json_file)
        except ValueError as v_exc:
            g.logger.error(
                f"{lp} JSON error -> loading access token from file, removing file... \n{v_exc}"
            )
            os.remove(jwt_file)
            access_token = None
        else:
            generated = data["time"]
            expires = data["expires"]
            access_token = data["token"]
            # epoch timestamp
            now = time.time()
            # lets make sure there is at least 30 secs left
            if int(now + 30 - generated) >= expires:
                g.logger.debug(
                    f"{lp} found access token, but it has or is about to expire. Need to login to MLAPI host..."
                )
                access_token = None
            else:
                g.logger.debug(
                    f"{lp} No need to login, access token is valid for {now - generated} sec",
                )
    # Get API access token
    if access_token is None:
        g.logger.debug(f"{lp} Requesting AUTH JWT from MLAPI")
        try:
            r = requests.post(
                url=ml_login_url,
                data=json.dumps(
                    {
                        "username": user,
                        "password": password,

                    }
                ),
                headers={"content-type": "application/json"},
            )
            r.raise_for_status()
        except Exception as ex:
            g.logger.error(f"{lp} ERROR request post -> \n{ex}")
            raise ValueError(f"NO_GATEWAY")
        else:
            data = r.json()
            access_token = data.get("access_token")
            if not access_token:
                g.logger.error(f"{lp} NO ACCESS TOKEN RETURNED! data={data}")
                raise ValueError(f"error getting remote API token")
            try:
                with open(jwt_file, "w") as json_file:
                    w_data = {
                        "token": access_token,
                        "expires": data.get("expires"),
                        "time": time.time(),
                    }
                    json.dump(w_data, json_file)
            except Exception as ex:
                g.logger.error(f"{lp} error while writing MLAPI AUTH JWT to disk!\n{ex}")
            else:
                g.logger.debug(2, f"{lp} writing MLAPI AUTH JWT to disk")
    return access_token


def remote_detect(options=None, args=None, route=None):
    """Sends an http request to mlapi host with data needed for inference"""
    # This uses mlapi (https://github.com/baudneo/mlapi) to run inference with the sent data and converts format to
    # what is required by the rest of the code.
    lp: str = "zmes:mlapi:"
    # print(f"{g.eid = } {options = } {g.api = } {args =}")
    model: str = "object"  # default to object
    access_token: Optional[str] = None
    auth_header = Optional[dict]
    show_header: Optional[dict] = None
    files: dict = {}
    # ml_routes integration, we know ml_enabled is True
    ml_api_url: Optional[str] = route['gateway']
    route_name: str = route['name'] or 'default_route'

    g.logger.info(
        f"|----------= Encrypted Route Name: '{route_name}' | Gateway URL: "
        f"'{ml_api_url if not str2bool(g.config.get('sanitize_logs')) else g.config.get('sanitize_str')}' | "
        f"Weight: {route['weight']} =----------|"
    )
    ml_object_url: str = f"{ml_api_url}/detect/object?type={model}"

    if not route.get("user") or not route.get("pass"):
        g.logger.error(f"{lp} No MLAPI user/password configured")
        g.logger.log_close()
        exit(1)
    if not access_token:
        try:
            access_token = remote_login(route['user'], route['pass'], route['gateway'])
        except Exception as ex:
            g.logger.error(f"{lp} ERROR getting remote API token -> {ex}")
            raise ValueError(f"error getting remote API token")
        else:
            if not access_token:  # add a re login loop?
                raise ValueError(f"error getting remote API token")
            auth_header = {"Authorization": f"Bearer {access_token}"}
            show_header = {"Authorization": f"{auth_header.get('Authorization')[:30]}......"}

    params = {"delete": True, "response_format": "zm_detect"}

    file_image: Optional[np.ndarray] = None
    if args.get("file"):  # File Input
        g.logger.debug(
            2,
            f"{lp} --File -> reading image from '{args.get('file')}'",
        )
        file_image = cv2.imread(args.get("file"))  # read from file
        if (
                g.config.get("resize") and g.config["resize"] != "no"
        ):  # resize before converting to http serializable
            vid_w = g.config.get("resize", file_image.shape[1])
            image = resize_image(file_image, vid_w)
            _succ, jpeg = cv2.imencode(".jpg", image)
            if not _succ:
                g.logger.error(f"{lp} ERROR: cv2.imencode('.jpg', <FILE IMAGE>)")
                raise ValueError("--file Can't encode image on disk into jpeg")
            files = {
                "image": ("image.jpg", jpeg.tobytes(), 'application/octet')
            }
    # ml-overrides grabs the default value for these patterns because their actual values are held in g.config
    # we can send these now and enforce them? but if using mlapi should mlapiconfig.yml take precedence over
    # ml_overrides? model_sequence already overrides mlapi, so..... ???
    ml_overrides: dict = {
        # Only enable when we are running with --file
        "enable": True if args.get('file') else False,
        "model_sequence": g.config["ml_sequence"].get("general", {}).get("model_sequence"),
        "object": {
            "pattern": g.config["ml_sequence"]
                .get("object", {})
                .get("general", {})
                .get("object_detection_pattern")
        },
        "face": {
            "pattern": g.config["ml_sequence"]
                .get("face", {})
                .get("general", {})
                .get("face_detection_pattern")
        },
        "alpr": {
            "pattern": g.config["ml_sequence"]
                .get("alpr", {})
                .get("general", {})
                .get("alpr_detection_pattern")
        },
    }
    # Get api credentials ready
    encrypted_data: Optional[dict] = None
    try:
        from cryptography.fernet import Fernet
        # assign Fernet object to a variable
    except ImportError:
        g.logger.error(
            f"{lp} the cryptography library does not seem to be installed! Please install using -> "
            f"(sudo) pip3 install cryptography"
        )
        Fernet = None
        # raise an exception to trigger the next route or local fallback
        raise ValueError(f"cryptography library not installed or not accessible")
    else:
        encrypted_data = {}
        try:
            # encode str into bytes for encryption use
            key: str = route['enc_key'].encode('utf-8')
            # get the credential data needed to pass mlapi
            kickstart: dict = g.api.cred_dump()
            # init the Fernet object with the encryption key
            f: Fernet = Fernet(key=key)
        except Exception as exc:
            g.logger.error(
                f"{lp} it appears the encryption key provided is malformed! "
                f"check the encryption key in route '{route_name}'"
            )
            g.logger.error(exc)
            # raise an exception to trigger the next route or local fallback
            raise ValueError(f"encryption key malformed for {route_name}")
        # Auth type and creds based on which type
        auth_type: str = g.api.auth_type
        if auth_type == 'token':
            kickstart['api_url'] = g.api.api_url
            kickstart['portal_url'] = g.api.portal_url
            encrypted_data = {
                f.encrypt(str(k).encode('utf-8')).decode(): f.encrypt(str(v).encode('utf-8')).decode()
                for k, v in kickstart.items() if v is not None
            }
            # Add the route name after encryption so that it is readable on the other end
            encrypted_data['name'] = route_name
        else:
            g.logger.error(f"{lp} Only JWT Auth token is supported (no basic auth),"
                           f" please upgrade to using that auth method!")
            g.logger.log_close()
            exit(1)
    # ------------------------------ Encryption END ---------------------------------
    # Ensure that the resize gets passed along
    if not options.get('resize') and g.config.get('resize'):
        # make 'resize' activated by just having a value in the config
        options['resize'] = g.config['resize']
    mlapi_json: dict = {
        "version": __app_version__,
        "mid": g.mid,
        "reason": args.get("reason"),
        "stream": g.eid,
        "stream_options": options,
        "ml_overrides": ml_overrides,
        "sub_options": None,
        "encrypted data": encrypted_data,
    }
    # files = {
    #     'document': (local_file_to_send, open(local_file_to_send, 'rb'), 'application/octet'),
    #     'datas' : ('datas', json.dumps(datas), 'application/json'),
    # }
    if files:
        # If we are sending a file we must add the JSON to the files dict (flask interprets this as a multipart)
        files['json'] = (json.dumps(mlapi_json))
    g.logger.debug(
        2,
        f"\n** Gateway URL: '"
        f"{ml_object_url if not str2bool(g.config.get('sanitize_logs')) else g.config.get('sanitize_str')}'"
        f" using auth_header={show_header} \n**** {params=}\n****** JSON: "
        f"stream: {mlapi_json['stream']} - mid: {mlapi_json['mid']} - reason: {mlapi_json['reason']} - "
        f"stream options: {mlapi_json['stream_options']} - files: {files}\n"
    )
    try:
        from requests_toolbelt.multipart import decoder
        r: requests.post = requests.post(
            url=ml_object_url,
            headers=auth_header,
            params=params,
            # json doesnt send when sending files to mlapi, so we send the file and the json together
            json=mlapi_json if not files else None,
            files=files,
        )
        r.raise_for_status()
    except ValueError as v_ex:
        # pass as we will do a retry loop? -> urllib3 has a retry loop built in but idk if that works here
        if v_ex == "BAD_IMAGE":
            pass
    except requests.exceptions.HTTPError as http_ex:
        if http_ex.response.status_code == 400:
            if args.get('file'):
                g.logger.error(
                    f"There seems to be an error trying to send an image from zmes to mlapi,"
                    f" looking into it. Please open an issue with sanitized logs!"
                )
            else:
                g.logger.error(f"{http_ex.response.json()}")
        elif http_ex.response.status_code == 500:
            g.logger.error(f"There seems to be an Internal Error with the mlapi host, check mlapi logs!")
        elif http_ex.response.status_code == 422:
            if http_ex.response.content == b'{"message": "Invalid token"}':
                g.logger.error(f"Invalid JWT AUTH token, trying to delete and re create...")
                _file_name = _get_jwt_filename(route['gateway'])
                jwt_file = f"{g.config['base_data_path']}/{_file_name}_login.json"  # mlapi access_token
                if Path(jwt_file).is_file():
                    try:
                        os.remove(jwt_file)
                    except Exception as e:
                        g.logger.error(f"{lp} error removing {jwt_file} -> {e}")
                    else:
                        g.logger.debug(f"{lp} Removed JWT file: {jwt_file}")
            else:
                g.logger.error(f"There seems to be an Authentication Error with the mlapi host, check mlapi logs!")
        else:
            g.logger.error(f"ERR CODE={http_ex.response.status_code}  {http_ex.response.content=}")
    except urllib3.exceptions.NewConnectionError as urllib3_ex:
        g.logger.debug(f"{lp} {urllib3_ex.args=} {urllib3_ex.pool=}")
        g.logger.error(
            f"There seems to be an error while trying to start a new connection to the mlapi host -> {urllib3_ex}")
    except requests.exceptions.ConnectionError as req_conn_ex:
        g.logger.error(
            f"There seems to be an error while trying to start a new connection to the mlapi host (is mlapi running?) "
            f"-> "
            f"{req_conn_ex.response}"
        )
    except Exception as all_ex:
        g.logger.error(
            f"{lp} error during post to mlapi host-> {all_ex}"
        )
        g.logger.debug(f"traceback-> {format_exc()}")
    else:
        data: Optional[dict] = None
        multipart_data: decoder.MultipartDecoder = decoder.MultipartDecoder.from_response(r)
        part: decoder.MultipartDecoder.from_response
        img: Optional[np.ndarray] = None
        for part in multipart_data.parts:
            if (
                    part.headers.get(b'Content-Type') == b'image/jpeg'
                    or part.headers.get(b'Content-Type') == b'application/octet'
            ):
                g.logger.debug(
                    f"{lp} decoding jpeg from the multipart response")
                img = part.content
                img = np.frombuffer(img, dtype=np.uint8)
                img = cv2.imdecode(img, cv2.IMREAD_UNCHANGED)

            elif part.headers.get(b'Content-Type') == b'application/json':
                g.logger.debug(f"{lp} parsed JSON detection data from the multipart response")
                data = json.loads(part.content.decode('utf-8'))

        if img is not None and len(img.shape) <= 3:
            # check if the image is already resized to the configured 'resize' value
            if options.get("resize", 'no') != "no" and options.get('resize') != img.shape[1]:
                img = resize_image(img, options.get("resize"))
            data["matched_data"]["image"] = img
        return data


def get_es_version() -> str:
    # Get zmeventnotification.pl VERSION
    es_version: str = '(?)'
    try:
        from shutil import which
        es_version = subprocess.check_output(
            [which("zmeventnotification.pl"), "--version"]
        ).decode("ascii")
    except Exception as all_ex:
        g.logger.error(f"{lp} ERROR while grabbing zmeventnotification.pl VERSION -> {all_ex}")
        es_version = "Unknown"
        pass
    return es_version.rstrip()


def _parse_args():
    ap = ArgumentParser()
    ap.add_argument("--docker", action="store_true", help="verbose output")
    ap.add_argument('--new', help="a flag to indicate the new (1.35.7) Event<Start/End>Command system", action='store_true')
    ap.add_argument(
        "-et",
        "--event-type",
        help="event type-> start or end",
        default="start"
    )
    ap.add_argument(
        "-c",
        "--config",
        help="config file with path Default: /etc/zm/objectconfig.yml",
        default="/etc/zm/objectconfig.yml",
    )
    ap.add_argument("-e",
                    "--event-id",
                    "--eventid",
                    dest='eventid',
                    help="event ID to retrieve (Required)"
                    )
    ap.add_argument(
        "-p",
        "--eventpath",
        help="path to store objdetect image file, usually passed by perl script",
        default="",
    )
    ap.add_argument(
        "-m",
        "--monitor-id",
        help="monitor id - For use by the PERL script (Automatically found)",
    )
    ap.add_argument(
        "-v", "--version", help="print version and quit", action="store_true"
    )
    ap.add_argument(
        "--bareversion", help="print only app version and quit", action="store_true"
    )
    ap.add_argument(
        "-o",
        "--output-path",
        help="internal testing use only - path for debug images to be written",
    )
    ap.add_argument(
        "-f", "--file", help="internal testing use only - skips event download"
    )
    ap.add_argument(
        "-r",
        "--reason",
        help="reason for event (notes field in ZM i.e -> Motion:Front Yard)",
    )
    ap.add_argument(
        "-n",
        "--notes",
        help="updates notes field in ZM with detections",
        action="store_true",
    )
    ap.add_argument(
        "-d", "--debug", help="enables debug with console output", action="store_true"
    )
    ap.add_argument(
        "-bd",
        "--baredebug",
        help="enables debug without console output (if monitoring log files with 'tail -F', as an example)",
        action="store_true",
    )

    ap.add_argument(
        "-lv",
        "--live",
        help="this is a live event (used internally by perl script; affects logic)",
        action="store_true",
    )

    args, u = ap.parse_known_args()
    args = vars(args)
    if not args:
        print(f"{lp} ERROR-FATAL -> no args!")
        exit(1)
    else:
        if args.get("version"):
            print(f"app:{__app_version__}, pyzm:{pyzm_version}")
            exit(0)
        if args.get("bareversion"):
            print(f"{__app_version__}")
            exit(0)

        if not args.get("config"):
            # check if there is a default config file
            if Path("/etc/zm/objectconfig.yml").is_file():
                args["config"] = "/etc/zm/objectconfig.yml"
            else:
                print("--config required (Default: '/etc/zm/objectconfig.yml' does not exist)")
                exit(1)
        else:
            # Validate the config file path
            if not Path(args['config']).exists():
                print(f"the --config file you passed does not exist! Please check your input!")
                exit(1)
            elif not Path(args['config']).is_file():
                print(f"the --config file you passed is not an actual file! Please check your input!")
                exit(1)

        if not args.get("file") and not args.get("eventid"):
            print("--eventid <Event ID #> or --file </path/to/file.(jpg/png/mp4)> REQUIRED")
            exit(1)
    return args


def main_handler():
    def _zmes_db():
        start_db = time.perf_counter()
        # From @pliablepixels work
        db_config = {
            'conf_path': os.getenv('PYZM_CONFPATH', '/etc/zm'),  # we need this to get started
            'dbuser': os.getenv('PYZM_DBUSER'),
            'dbpassword': os.getenv('PYZM_DBPASSWORD'),
            'dbhost': os.getenv('PYZM_DBHOST'),
            'dbname': os.getenv('PYZM_DBNAME'),
            'driver': os.getenv('PYZM_DBDRIVER', 'mysql+mysqlconnector')
        }
        # read all config files in order
        files = []
        # Pythonic?
        # map(files.append, glob.glob(f'{db_config["conf_path"]}/conf.d/*.conf'))
        for f in glob.glob(f'{db_config["conf_path"]}/conf.d/*.conf'):
            files.append(f)
        files.sort()
        files.insert(0, f"{db_config['conf_path']}/zm.conf")
        config_file = ConfigParser(interpolation=None, inline_comment_prefixes='#')
        f = None
        try:
            for f in files:
                with open(f, 'r') as s:
                    # print(f'reading {f}')
                    # This adds [zm_root] section to the head of each zm .conf.d config file,
                    # not physically only in memory
                    config_file.read_string(f'[zm_root]\n{s.read()}')
        except Exception as exc:
            g.logger.error(f"Error opening {f if f else files} -> {exc}")
            g.logger.error(f"{format_exc()}")
            print(f"Error opening {f if f else files} -> {exc}")
            print(f"{format_exc()}")
            g.logger.log_close(exit=1)
            exit(1)
        else:
            conf_data = config_file['zm_root']
            if not db_config.get('dbuser'):
                db_config['dbuser'] = conf_data.get('ZM_DB_USER')
            if not db_config.get('dbpassword'):
                db_config['dbpassword'] = conf_data.get('ZM_DB_PASS')
            if not db_config.get('dbhost'):
                db_config['dbhost'] = conf_data.get('ZM_DB_HOST')
            if not db_config.get('dbname'):
                db_config['dbname'] = conf_data.get('ZM_DB_NAME')

        cstr = f"{db_config['driver']}://{db_config['dbuser']}:{db_config['dbpassword']}@" \
               f"{db_config['dbhost']}/{db_config['dbname']}"
        try:
            engine = create_engine(cstr, pool_recycle=3600)
            conn = engine.connect()
        except SQLAlchemyError as e:
            conn = None
            engine = None
            g.logger.error(f"DB configs - {cstr}")
            g.logger.error(f"Could not connect to DB, message was: {e}")
        else:
            meta = MetaData(engine)
            # New reflection
            meta.reflect(only=['Events'])
            e_select = select([meta.tables['Events'].c.MonitorId]).where(meta.tables['Events'].c.Id == g.eid)
            select_result: ResultProxy = conn.execute(e_select)
            mid: Optional[Union[str, int]] = None
            for row in select_result:
                mid = row[0]
            if mid:
                g.mid = int(mid)
                g.logger.debug(f"{lp} ZM DB SET GLOBAL MONITOR ID!")
            select_result.close()
            conn.close()
            engine.dispose()
            g.logger.debug(f"perf:ZM DB: time to grab Monitor ID ({g.mid}): {time.perf_counter() - start_db:.4f}")
    bg_db: Thread = Thread(name='db_thread', target=_zmes_db, daemon=True)
    # Hack to get the VERIFIED monitor ID, until the monitor ID is passed along with the EventID for EventCommandStart
    bg_db.start()

    # perf counters
    start_of_script: time.perf_counter = time.perf_counter()
    total_time_start_to_detect: time.perf_counter
    start_of_after_detection: time.perf_counter
    start_of_remote_detection: Optional[time.perf_counter] = None
    start_of_local_detection: Optional[time.perf_counter] = None
    start_of_local_fallback_detection: Optional[time.perf_counter] = None
    # Threads
    bg_animations: Optional[Thread] = None
    bg_pushover_jpg: Optional[Thread] = None
    bg_pushover_gif: Optional[Thread] = None
    bg_mqtt: Optional[Thread] = None
    # images
    objdetect_jpeg_image: Optional[np.ndarray] = None
    pushover_image: Optional[np.ndarray] = None
    # vars
    final_msg: str = ''
    old_notes: str = ''
    notes_zone: str = ''
    notes_cause: str = ''
    prefix: str = ''
    pred: str = ''
    detections: list = []
    seen: list = []
    remote_sanitized: dict = {}
    ml_options: dict = {}
    stream_options: dict = {}
    matched_data: dict = {}
    all_data: dict = {}
    obj_json: dict = {}
    m: pyzm.ml.detect_sequence.DetectSequence
    matched_data: dict
    pushover: pyzm.helpers.pyzm_utils.Pushover
    c_u: str = ''
    c_pw: str = ''
    bio: BytesIO
    past_event: bool = False
    _frame_id: str = ''
    lp: str = "zmes:"
    # -------------- END vars -------------------
    from pyzm.helpers.pyzm_utils import LogBuffer
    # first time instantiating the GlobalConfig Object
    global g
    g = GlobalConfig()
    g.DEFAULT_CONFIG = DEFAULT_CONFIG
    g.logger = LogBuffer()
    # Process CLI arguments
    args = _parse_args()
    if args.get('new'):
        from pyzm.helpers.pyzm_utils import time_format
        print(f"ZONEMINDER: EventStartCommand was called -> {time_format(datetime.now())}")
        exit(0)
    # process the config using the arguments
    g.eid = args.get("eventid", args.get("file"))
    start_conf: time.perf_counter = time.perf_counter()
    from pyzm.helpers.new_yaml import process_config as proc_conf
    zmes_config, g = proc_conf(args=args, type_='zmes')
    g.logger.debug(f"perf:{lp} building the initial config took {time.perf_counter() - start_conf}")
    bg_api_thread: Thread = Thread(name="ZM API", target=create_api, kwargs={'args': args})
    bg_api_thread.start()

    objdet_force = str2bool(g.config.get("force_debug"))
    et = args.get("event_type")
    g.logger.info(
        f"------|  FORKED NEO --- app->Hooks: {__app_version__} - pyzm: {pyzm_version} - ES: {get_es_version()}"
        f" - OpenCV:{cv2.__version__} |------"
    )
    if args.get('monitor_id') and (args.get('live') or args.get('new')):
        # live is from the perl daemon, new is from the EventCommandStart which will hopefully have the mid in it
        g.logger.debug(f"{lp} Monitor ID provided by a trusted source, skipping monitor ID verification...")
        if args.get('monitor_id'):
            g.config['mid'] = g.mid = int(args["monitor_id"])
    if not g.mid:
        start_wait = time.perf_counter()
        g.logger.debug(f"{lp} waiting for the monitor ID to be verified!")
        if bg_db and bg_db.is_alive():
            g.logger.debug(f"{lp} waiting for the ZM DB thread to finish...")
            bg_db.join()
        if g.mid:
            g.logger.debug(
                f"perf:{lp} Monitor ID ({g.mid}) verified! pausing to wait for verification took "
                f"{time.perf_counter() - start_wait} seconds"
            )
    if not g.mid and not args.get('file'):
        msg = (f"{lp} SOMETHING is very WRONG! g.mid is not populated after waiting for the API object and ZM DB to "
               f"be created in background EXITING")
        g.logger.debug(msg)
        print(msg)
        g.logger.log_close()
        exit(1)
    if g.mid in zmes_config.monitors:
        g.logger.debug(f"{lp} Monitor ID ({g.mid}) has an overrode config, switching to it!")
        # only need to build 1 override
        zmes_config.monitor_override(g.mid)
        # override the global config with the overrode per monitor config
        g.config = zmes_config.monitor_overrides[g.mid]
    else:
        g.logger.debug(f"{lp} Monitor ID ({g.mid}) does not have an overrode config, using the base config!")
        g.config = zmes_config.config

    # Main thread needs to handle the signals
    try:
        from pyzm.ZMLog import sig_intr, sig_log_rot
        g.logger.info(f"{lp} Setting up signal handlers for log 'rotation' and 'interrupt'")
        signal.signal(signal.SIGHUP, partial(sig_log_rot, g))
        signal.signal(signal.SIGINT, partial(sig_intr, g))
    except Exception as e:
        g.logger.error(f'{lp} Error setting up log rotate and interrupt signal handlers -> \n{e}\n')
        raise e

    bg_logger = Thread(name="ZMLog", target=start_logs,
                       kwargs={'config': g.config, 'args': args, 'type_': 'zmes', 'no_signal': True})
    bg_logger.start()
    if args.get("file"):
        g.config["wait"] = 0
        g.config["write_image_to_zm"] = "no"
    if args.get("output_path"):
        g.logger.debug(
            f"{lp}:init: 'output_path' modified to '{args.get('output_path')}'"
        )
        g.config["image_path"] = args.get("output_path")
        g.config["write_debug_image"] = "yes"
    # see if we need to skip doing any detections, this is a more configurable option as no need to restart the ES
    # zmeventnotification.pl to update this list, objectconfig.yml is reevaluated every event
    skip: Union[str, list] = g.config.get("skip_mons")
    skip = skip.split(",") if skip and isinstance(skip, str) else []
    if (
            str(g.mid) in skip and args.get("live")
    ):  # Only skip if configured and its a live event
        g.logger.info(
            f"{lp} event {g.eid} from monitor: '{g.config['mon_name']}' ID: {g.mid}"
            f" which is in the list of monitors to skip (skip_mons) -> {skip}  "
        )
        g.logger.log_close()
        exit(0)
    stream_options = g.config.get('stream_sequence')
    if zmes_config.polygons.get(g.mid):
        stream_options['polygons'] = zmes_config.polygons[g.mid]
    ml_options = g.config.get('ml_sequence')
    # perl script (zmeventnotification.pl) modified to send 'live' flag for event start/end`
    if not args.get('file') and (not args.get("live") and not str2bool(g.config.get("force_live"))):
        stream_options["PAST_EVENT"] = g.config["PAST_EVENT"] = past_event = True
        g.logger.debug(f"{lp} this is a 'PAST' (debugging?) event!")
    elif not args.get('file') and (not args.get("live") and str2bool(g.config.get("force_live"))):
        g.logger.debug(f"{lp} forcing 'LIVE' event logic on a past event!")
    elif args.get('file'):
        g.logger.debug(
            f"{lp} --file INPUT so LIVE / PAST event logic untouched -> {g.config.get('PAST_EVENT')=} "
            f"{stream_options.get('PAST_EVENT')=} {past_event=}"
        )
    if str2bool(g.config["ml_enable"]):  # send to mlapi host
        mlapi_success: bool = False
        remote_response: dict = {}
        tries: int = 0
        ml_routes: Optional[Union[list, str]] = g.config.get('ml_routes')
        if isinstance(ml_routes, str):
            ml_routes = literal_eval(ml_routes)
        weighted_routes = sorted(ml_routes, key=lambda _route: _route['weight'])
        start_of_remote_detection = time.perf_counter()
        total_time_start_to_detect = start_of_remote_detection - start_of_script
        for x in range(len(weighted_routes)):
            tries += 1
            route = weighted_routes.pop(0)
            if remote_response:
                break
            if not str2bool(route.get('enabled')):
                g.logger.debug(f"{lp} route #{tries} ({route['name']}) is disabled, skipping")
                continue
            try:
                if tries > 1:
                    g.logger.debug(f"{lp} switching to the next route '{route['name']}'")
                remote_response = remote_detect(options=stream_options, args=args, route=route)
            except requests.exceptions.HTTPError as http_ex:
                if not weighted_routes:
                    start_of_remote_detection = time.perf_counter() - start_of_remote_detection
                if http_ex.response.status_code == 400:
                    if args.get('file'):
                        g.logger.warning(
                            f"{lp} ERR 400 -> there seems to be an error trying to send an image from "
                            f"zm_detect to mlapi, looking into it -> {http_ex.response.json()}"
                        )
                    else:
                        # todo: pushover error
                        g.logger.warning(
                            f"{lp} ERR 400 -> {http_ex.response.json()}"
                        )
                if http_ex.response.status_code == 500:
                    # todo: pushover error
                    g.logger.warning(
                        f"{lp} ERR 500 -> there seems to be an Internal Error with the mlapi host, check"
                        f" mlapi logs! -> {http_ex.response.json()}"
                    )
                else:
                    g.logger.warning(
                        f"{lp} ERR {http_ex.response.status_code} -> "
                        f"HTTP ERROR --> {http_ex.response.json()}"
                    )
            except ValueError as exc:
                if not weighted_routes:
                    start_of_remote_detection = time.perf_counter() - start_of_remote_detection
            except Exception as all_ex:
                if not weighted_routes:
                    start_of_remote_detection = time.perf_counter() - start_of_remote_detection
                g.logger.warning(f"{lp} there was an error during the remote detection! -> {all_ex}")
                g.logger.debug(format_exc())
            # Successful mlapi post
            else:
                start_of_remote_detection = time.perf_counter() - start_of_remote_detection

                mlapi_success = True
                if remote_response is not None:
                    matched_data = remote_response.get("matched_data")
                    remote_sanitized: dict = copy.deepcopy(remote_response)
                    remote_sanitized["matched_data"]["image"] = "<uint-8 encoded jpg>" if matched_data.get(
                        'image') is not None else "<No Image Returned>"
                mon_name = f"'Monitor': {g.config.get('mon_name')} ({g.mid})->'Event': "
                g.logger.debug(
                    f"perf:{lp}mlapi: {f'{mon_name}' if not args.get('file') else ''}{g.eid}"
                    f" mlapi detection took: {start_of_remote_detection}"
                )
                break
        if str2bool(g.config.get('ml_fallback_local')) and not mlapi_success:

            start_of_local_fallback_detection = time.perf_counter()
            total_time_start_to_detect = start_of_local_fallback_detection - start_of_script

            g.logger.error(f"{lp} mlapi error, falling back to local detection")
            stream_options["polygons"] = zmes_config.polygons.get(g.mid)
            from pyzm.ml.detect_sequence import DetectSequence
            m = DetectSequence(options=ml_options)
            matched_data, all_data, all_frames = m.detect_stream(
                stream=g.eid,
                options=stream_options,
                in_file=True if args.get('file') else False
            )
            start_of_local_fallback_detection = time.perf_counter() - start_of_local_fallback_detection

    else:  # mlapi not configured, local detection
        start_of_local_detection = time.perf_counter()
        total_time_start_to_detect = start_of_local_detection - start_of_script

        if not args.get("file") and float(g.config.get("wait", 0)) > 0.0:
            g.logger.info(
                f"{lp}local: sleeping for {g.config['wait']} seconds before running models"
            )
            time.sleep(float(g.config["wait"]))
        try:
            from pyzm.ml.detect_sequence import DetectSequence
            m = DetectSequence(options=g.config['ml_sequence'])
            print('doing local detection')
            matched_data, all_data, all_frames = m.detect_stream(
                stream=g.eid, options=stream_options,
                in_file=True if args.get('file') else False
            )
        except Exception as all_ex:
            # todo: pushover error
            g.logger.debug(f"{lp}local: TPU and GPU in ZM DETECT? --> {all_ex}")
        else:
            g.logger.debug(f"perf:{lp}local: detection took: {time.perf_counter() - start_of_local_detection}")

    # This is everything after a detection has been ran
    start_of_after_detection = time.perf_counter()

    if matched_data is not None:
        # Format the frame ID (if it contains s- for snapshot conversion)
        _frame_id = grab_frameid(matched_data.get("frame_id"))
        obj_json = {
            "frame_id": _frame_id,
            "labels": matched_data.get("labels"),
            "confidences": matched_data.get("confidences"),
            "boxes": matched_data.get("boxes"),
            "image_dimensions": matched_data.get("image_dimensions"),
        }
        # Print returned data nicely if there are any detections returned
        if len(matched_data.get("labels")):
            pretty_print(matched_data=matched_data, remote_sanitized=remote_sanitized)

        prefix = f"[{str(matched_data.get('frame_id', 'x')).strip('-')}] "

        for idx, l in enumerate(
                matched_data.get("labels")
        ):  # add the label, confidence and model name if configured
            if l not in seen:
                label_txt = ""
                model_txt = (
                    matched_data.get("model_names")[idx]
                    if str2bool(g.config.get("show_models"))
                    else ""
                )
                if not str2bool(g.config.get("show_percent")):
                    label_txt = f"{l}{f'({model_txt})' if model_txt != '' else ''}, "
                else:
                    label_txt = (
                        f"{l}({matched_data['confidences'][idx]:.0%}"
                        f"{f'-{model_txt}' if model_txt != '' else ''}), "
                    )
                pred = f"{pred}{label_txt}"
                seen.append(l)

    if pred != '' and matched_data['image'] is not None:
        wrote_objdetect = None
        send_push = False
        # building the keyword that zm_event_start/end and the perl script look for -> detected:
        pred = pred.strip().rstrip(",")  # remove trailing comma
        pred_out = f"{prefix}:detected:{pred}"
        pred = f"{prefix}{pred}"
        new_notes = pred_out

        g.logger.info(f"{lp}prediction: '{pred}'")
        jos = json.dumps(obj_json)
        g.logger.debug(f"{lp}prediction:JSON: {jos}")
        # this is what sends the detection back to the perl script, --SPLIT-- is what splits the data structures
        if not args.get('file') and not past_event:
            print(f"\n{pred_out.rstrip()}--SPLIT--{jos}\n")

        if not g.api_event_response and not args.get('file'):
            g.logger.debug(f"{lp} in the after detection - API event data not populated, retrieving now")
            g.Event, g.Monitor, g.Frame = g.api.get_all_event_data()

        if not args.get('file') and g.Event.get("Notes"):
            old_notes = g.Event.get("Notes")
            p = r".*detected.*"
            matches = findall(p, old_notes)
            if matches:  # we have written here before
                notes_zone = old_notes.split(":")[-1]
                new_notes = f"{new_notes} {g.config.get('api_cause')}: {notes_zone.strip()}"
            else:
                # zone that set the motion alarm off or if its linked the monitor
                # that it as linked from, we pull this from the API anyways
                notes_zone = old_notes.split(":")[-1]
                new_notes = f"{new_notes} {g.config.get('api_cause')}: {notes_zone.strip()}"
        (
            objdetect_jpeg_image,
            display_param_dict,
            param_dict,
            delete_push_image,
            push_image_name,
        ) = (None, None, None, None, None)
        if matched_data["image"] is not None:  # We have an image to work with
            # prepare frame with bounding box, polygon of specified zone and labels with conf/model name
            # show confidence percent in annotated images
            show_percent = str2bool(g.config.get("show_percent"))
            # show red bounding boxes around objects that were detected but filtered out
            errors_ = (
                matched_data["error_boxes"]
                if str2bool(g.config.get("show_filtered_detections", True))
                else None
            )
            # draw polygon/zone
            draw_poly = (
                matched_data["polygons"]
                if str2bool(g.config.get("draw_poly_zone"))
                else None
            )
            # ---------------------------------------------------------------------------------
            # todo - can be calculated with original and resize x,y
            # we sent a file over for detection and need to rescale the returned bounding boxes
            if args.get('file') and matched_data.get('image_dimensions'):
                dimensions = matched_data.get('image_dimensions')
                # image_dimensions -->{'original': [2160, 3840], 'resized': [450, 800]}]
                old_h, old_w = dimensions["original"]
                new_h, new_w = dimensions["resized"]
                old_x_factor = new_w / old_w
                old_y_factor = new_h / old_h
                g.logger.debug(2,
                               f"{lp} image was resized and needs scaling of bounding boxes "
                               f"using factors of x={old_x_factor} y={old_y_factor}")
                print(f"BEFORE: {matched_data['boxes']}")
                for box in matched_data['boxes']:
                    box[0] = round(box[0] / old_x_factor)
                    box[1] = round(box[1] / old_y_factor)
                    box[2] = round(box[2] / old_x_factor)
                    box[3] = round(box[3] / old_y_factor)
                print(f"AFTER {matched_data['boxes']}")

            # ---------------------------------------------------------------------------------

            # create an output image that will have the red bounding boxes around detections that were filtered out
            # by confidence/zone/match pattern/etc. (if configured), a timestamp in upper left corner, random color
            # bounding box' around matched detections with their label, confidence level and the model name that
            # detected it (if configured)
            # debug image will have the red bounding boxes (if configured)
            # ---------- CREATE THE AANNOTATED IMAGE (objdetect.jpg) ----------------------------
            objdetect_jpeg_image = draw_bbox(
                image=matched_data["image"],
                boxes=matched_data["boxes"],
                labels=matched_data["labels"],
                confidences=matched_data["confidences"],
                polygons=draw_poly,
                poly_thickness=g.config["poly_thickness"],
                poly_color=g.config["poly_color"],
                write_conf=show_percent,
                errors=errors_,
                write_model=str2bool(g.config.get("show_models")),
                models=matched_data.get("model_names"),
            )
            # objdetect_jpeg_image = cv2.cvtColor(objdetect_jpeg_image, cv2.COLOR_BGR2RGB)

            # Create animations as soon as we have a frame ready to process,
            # no timestamp as thats controlled by a different config option
            if (
                    not args.get('file') and
                    str2bool(g.config.get("create_animation"))
                    and (
                    (not past_event)
                    or (past_event and str2bool(g.config.get("force_animation")))
                    or (past_event and objdet_force)
            )
            ):
                g.logger.debug(
                    f"{lp}animation: gathering data to start animation creation in background...",
                )
                # grab event data if we don't already have it
                if bg_api_thread and bg_api_thread.is_alive():
                    bg_api_thread.join(5)
                if not g.api_event_response:
                    g.Event, g.Monitor, g.Frame = g.api.get_all_event_data()
                try:
                    from pyzm.helpers.pyzm_utils import createAnimation
                    # how long it takes to create the animations
                    animation_seconds = time.perf_counter()
                    opts = {
                        'fid': _frame_id,
                        'file name': f"{args.get('eventpath')}/objdetect",
                        'conf globals': g,

                    }
                    bg_animations = Thread(
                        target=createAnimation,
                        kwargs={
                            "image": objdetect_jpeg_image.copy(),
                            "options": opts,
                            "perf": animation_seconds
                        },
                    )
                except Exception as all_ex:
                    g.logger.error(
                        f"{lp}animation: CREATING THREAD err_msg-> {all_ex}"
                    )
                else:  # Creating thread was successful
                    bg_animations.start()  # kick the animation creation off in background

        # Create and draw timestamp on objectdetect.jpg
        ts_: dict = g.config.get('picture_timestamp', {})
        if (
                ts_
                and str2bool(ts_.get('enabled'))
                and not args.get('file')
        ):
            objdetect_image_w, objdetect_image_h = objdetect_jpeg_image.shape[:2]
            grab_frame = int(_frame_id) - 1  # convert to index
            if grab_frame > g.event_tot_frames:  # frame buffer mismatch, refresh the 'event' API call
                if not g.api:
                    create_api(args)
                g.Event, g.Monitor, g.Frame = g.api.get_all_event_data()
            ts_format = ts_.get('date format', '%Y-%m-%d %H:%M:%S.%f')
            try:
                image_ts_text = (
                    f"{datetime.strptime(g.Frame[grab_frame].get('TimeStamp'), ts_format)}"
                    if g.Frame and g.Frame[grab_frame]
                    else datetime.now().strftime(ts_format)
                )
                if str2bool(ts_.get('monitor id')):
                    image_ts_text = f"{image_ts_text} - {g.config.get('mon_name')} ({g.mid})"
            except IndexError:  # frame ID converted to index isn't there? make the timestamp now()
                image_ts_text = datetime.now().strftime(ts_format)
            ts_text_color = ts_.get('text color')
            ts_bg_color = ts_.get('bg color')
            ts_bg = str2bool(ts_.get("background"))
            objdetect_jpeg_image = write_text(
                frame=objdetect_jpeg_image,
                text=image_ts_text,
                text_color=ts_text_color,
                x=5,
                y=30,
                w=objdetect_image_w,
                h=objdetect_image_h,
                adjust=True,
                bg=ts_bg,
                bg_color=ts_bg_color,
            )
        if str2bool(g.config.get("push_enable")) and not args.get('file'):  # pushover is enabled
            if not past_event or (
                    past_event and str2bool(g.config.get("push_force"))
            ):  # Live event or past event with push_force=yes
                from pyzm.helpers.pyzm_utils import Pushover
                # Pushover only accepts JPG/GIF as of November 2021, VOTE for mp4 support on their support 'Ideas' page
                # I had a chat with the dev of PushOver who said they are planning on adding mp4 support but are looking
                # for ways so they don't have to do any processing on their end, just receive and push it to devices
                pushover = Pushover()  # create pushover object
                param_dict = {
                    "token": g.config.get("push_token"),
                    "user": g.config.get("push_key"),
                    "title": f"({g.eid}) {g.config.get('mon_name')}:{g.config.get('api_cause')}->{notes_zone.strip()}",
                    "message": "",
                    "sound": g.config.get("push_sound", None),
                    # 'priority': 0,
                    # 'device': 'a specific device',
                }
                if et and isinstance(et, str) and et.lower() == "end":
                    param_dict["title"] = f"Ended-> {param_dict['title']}"
                if str2bool(g.config.get("push_url")):
                    # Credentials for pushover ZM user for viewing events in clickable URL, if none supplied uses
                    # api get_auth() which will use the credentials that you connect ZMES to ZM with
                    c_pw = urllib.parse.quote(g.config.get("push_pass"), safe="")
                    c_u = g.config.get("push_user")
                    # use user&pass if using a specific user for pushover notifications otherwise use api auth
                    # (token if API 2.0 else user and pass) should be using https
                    push_auth = (
                        f"user={c_u}&pass={c_pw}"
                        if c_u and c_pw
                        else f"{g.api.get_auth()}"
                    )
                    param_dict["url"] = (
                        f"{g.config.get('portal')}/cgi-bin/nph-zms?mode=jpeg&scale="
                        f"50maxfps=15&buffer=1000&replay=single&monitor={g.mid}&"
                        f"event={g.eid}&{push_auth}"
                    )
                    param_dict["url_title"] = "View event in browser"

                # g.logger.debug(f"{g.config.get('push_key') = } {param_dict.get('user') = }")

                # ---------------------------------
                #           HASS ADD ON
                # ---------------------------------
                resp = None
                ha_verified = verify_vals(g.config, {"hass_enable", "hass_server", "hass_token"})
                if (str2bool(g.config.get('push_emergency')) and (not past_event or (past_event and str2bool(g.config.get("push_emerg_force"))))):
                    g.logger.debug(f"{lp} pushover EMERGENCY notification enabled...")
                    emerg_mons: Union[str, set] = g.config.get('push_emerg_mons')
                    if emerg_mons:
                        proceed = True
                        emerg_labels = g.config.get('push_emerg_labels')
                        if emerg_labels:
                            emerg_labels = set(str(emerg_labels).strip().split(','))
                            if not any(w in emerg_labels for w in matched_data.get("labels")):
                                g.logger.debug(
                                    f"You have specified emergency labels that are not in the detected objects, "
                                    f"not sending an emergency alert...")
                                proceed = False

                        if proceed:
                            def time_in_range(start, end, current_):
                                """Returns whether current is in the range [start, end]"""
                                return start <= current_ <= end
                            # strip whitespace and convert the str into a list using a comma as the delimiter
                            # convert to a set to remove duplicates and then use set comprehension to ensure all int
                            emerg_mons = set(str(emerg_mons).strip().split(','))
                            emerg_mons = {int(x) for x in emerg_mons}
                            emerg_retry = int(g.config.get('push_emerg_retry', 120))
                            emerg_expire = int(g.config.get('push_emerg_expire', 3600))
                            emerg_time_start = g.config.get('push_emerg_time_start')
                            emerg_time_end = g.config.get('push_emerg_time_end')
                            import dateparser
                            current = datetime.now().timestamp()
                            tz = g.config.get('push_emerg_tz', {})
                            if tz:
                                tz = {'TIMEZONE': tz}
                                g.logger.debug(f'{lp} Converting to TimeZone: {tz}')
                            doit_ = False
                            if emerg_time_start and emerg_time_end:
                                emerg_time_start = dateparser.parse(emerg_time_start, settings=tz).timestamp()
                                emerg_time_end = dateparser.parse(emerg_time_end, settings=tz).timestamp()

                                doit_ = True
                            elif emerg_time_end:
                                emerg_time_start = dateparser.parse('midnight', settings=tz).timestamp()
                                emerg_time_end = dateparser.parse(emerg_time_end, settings=tz).timestamp()
                                doit_ = True
                            elif emerg_time_start:
                                emerg_time_end = dateparser.parse('23:59:59', settings=tz).timestamp()
                                emerg_time_start = dateparser.parse(emerg_time_start, settings=tz).timestamp()
                                doit_ = True
                            if g.mid in emerg_mons:
                                _doit = True
                                if doit_:
                                    g.logger.debug(f"{current = } -- {emerg_time_start = } -- {emerg_time_end = }")

                                    g.logger.debug(f"{lp} Checking current time to supplied timerange...")

                                    emerg_in_time = time_in_range(emerg_time_start, emerg_time_end, current)
                                    if not emerg_in_time:
                                        g.logger.debug(f"{lp} it is currently not within the specified time range for "
                                                       f"sending an emergency notification")
                                        _doit = False
                                if _doit:
                                    g.logger.debug(f"{lp} sending pushover emergency notification...")
                                    param_dict['priority'] = 2
                                    param_dict['retry'] = emerg_retry
                                    param_dict['expire'] = emerg_expire
                                    # Emergency notifications will bypass cooldown and off switch
                                    send_push = True
                if not send_push and ha_verified and str2bool(g.config.get("hass_enable")):
                    send_push = do_hass(g)
                    do_hast_micht = 'gefragt 🤘'

                # ---------------------------------
                # -- Send jpg image if not creating an animation or if creating animation and push_jpg is configured
                if send_push and (
                        not str2bool(g.config.get("create_animation"))
                        or (
                                str2bool(g.config.get("create_animation"))
                                and g.config.get("push_jpg")
                        )
                ):
                    # TODO: use cv2.imencode and cv2.BGR2RGB instead of PIL Image, cv2 already imported.
                    # convert image to a format that can be written to file, tried just cv2 but it's BGR
                    # cv2.imencode can take cv2.BGR2RGB apparently so ill try that instead of using PIL import
                    pushover_image = objdetect_jpeg_image.copy()
                    pushover_image = cv2.cvtColor(pushover_image, cv2.COLOR_BGR2RGB)
                    pushover_image = Image.fromarray(pushover_image)
                    bio = BytesIO()  # create buffer
                    # save push_image to virtual file buffer
                    pushover_image.save(bio, format="jpeg")

                    old_device = param_dict.get("device")
                    param_dict["message"] = (
                        f"{pred_out.strip()} Sent to pushover servers"
                        f"{datetime.now().strftime(' at: %H:%M:%S.%f')[:-3]}"
                    )
                    param_dict["device"] = (
                        g.config.get("push_debug_device")
                        if past_event
                        else old_device
                    )
                    display_param_dict = param_dict.copy()
                    old_key = param_dict.get("user")
                    old_token = param_dict.get("token")

                    if g.config.get("push_jpg"):
                        param_dict["token"] = g.config.get("push_jpg")
                        display_param_dict["token"] = "<push_jpg app token>"
                    else:
                        param_dict["token"] = old_token
                        display_param_dict["token"] = "<default app token>"
                    if g.config.get("push_jpg_key"):
                        param_dict["user"] = g.config.get("push_jpg_key")
                        display_param_dict["user"] = "<push_jpg_key user/group key>"
                    else:
                        param_dict["user"] = old_key
                        display_param_dict["user"] = "<default user/group key>"

                    display_auth = (
                        f"user={g.config['sanitize_str']}&pass={g.config['sanitize_str']}"
                        if c_u and c_pw
                        else f"{'<api 2.0+ auth token>' if not g.config.get('basic_user') else '<basic creds>'}"
                    )
                    display_url = (
                        f"{g.config.get('portal') if not str2bool(g.config.get('sanitize_logs')) else '{}'.format(g.config['sanitize_str'])}"
                        f"/cgi-bin/nph-zms?mode=jpeg&scale=50&maxfps=15&buffer=1000&replay=single&monitor="
                        f"{g.mid}&event={g.eid}&{display_auth}"
                    )
                    display_param_dict["url"] = display_url

                    if matched_data.get("labels"):

                        vehicles = ('truck', 'car', 'motorbike', 'bus')
                        # priority is in descending order
                        labels = tuple(matched_data.get("labels"))
                        if 'person' in labels and g.config.get('push_sound_person'):
                            param_dict['sound'] = g.config['push_sound_person']
                        elif any(w in vehicles for w in labels) and g.config.get('push_sound_vehicle'):
                            param_dict['sound'] = g.config['push_sound_vehicle']
                        elif 'car' in labels:
                            pass
                        elif 'truck' in labels:
                            pass
                        elif 'motorbike' in labels:
                            pass
                        elif 'dog' in labels:
                            pass
                        elif 'cat' in labels:
                            pass

                    files = {
                        "attachment": (
                            "objdetect.jpg",
                            bio.getbuffer(),
                            "image/jpeg",
                        )
                    }
                    g.logger.debug(f"{lp}pushover:JPG: data={display_param_dict} files='<objdetect.jpg>'")
                    rl = (
                        False
                        if str2bool(g.config.get("create_animation")) or past_event
                        else True
                    )
                    bg_pushover_jpg = Thread(
                        target=pushover.send,
                        kwargs={
                            "param_dict": param_dict,
                            "files": files,
                            "record_last": rl,
                        },
                    )
                    bg_pushover_jpg.start()
                    param_dict["token"] = old_token
                    param_dict["device"] = old_device
                    param_dict["user"] = old_key
            else:
                g.logger.debug(
                    f"{lp}pushover: this is a past event and 'push_force'"
                    f" is not configured, skipping pushover notifications..."
                )

        if not args.get('file'):
            # check if we have written objects.json and see if the past detection is the same is this detection
            skip_write = None
            jf = f"{args.get('eventpath')}/objects.json"
            json_file_ = Path(jf)
            if json_file_.is_file():
                try:
                    # Open objects.json and compare it to the current detection
                    with open(jf, "r") as ff:
                        eval_me = json.load(ff)
                except json.JSONDecodeError:
                    # If theres an issue, use a value that will not match
                    eval_me = {"test": 123, 321: 'test', 420: 69}
                if eval_me == obj_json:
                    # the previously saved detection is the same as the current one
                    skip_write = True
            if not skip_write or (skip_write and objdet_force):
                g.logger.debug(
                    f"{lp}{'FORCE:' if objdet_force and past_event else ''} writing objects.json and "
                    f"objdetect.jpg to '{args.get('eventpath')}'"
                )
                try:
                    cv2.imwrite(f"{args.get('eventpath')}/objdetect.jpg", objdetect_jpeg_image)
                    with open(jf, "w") as jo:
                        json.dump(obj_json, jo)
                except Exception as all_ex:
                    g.logger.error(f"{lp} Error trying to save objects.json or objdetect.jpg "
                                   f"err_msg-> \n{all_ex}\n"
                                   )
                else:
                    wrote_objdetect = True
            else:
                g.logger.debug(
                    f"{lp} not writing objdetect.jpg or objects.json as monitor {g.mid}->'{g.config.get('mon_name')}' "
                    f"event: {g.eid} has a previous detection and it matches the current one"
                )
            # GOTIFY / OTHER PUSH APIS
            if str2bool(g.config.get("custom_push")) and Path(g.config.get("custom_push_script")).is_file():
                # Get JWT auth token for push_user if configured
                c_pw = g.config.get("push_pass")
                c_u = g.config.get("push_user")
                push_zm_tkn = None
                login_data = {
                    "user": g.config.get("push_user"),
                    "pass": g.config.get("push_pass"),
                }
                url = f"{g.api.api_url}/host/login.json"
                try:
                    r = requests.post(url, data=login_data)
                    r.raise_for_status()
                    rj = r.json()
                except Exception as exc:
                    g.logger.error(f"{lp} Error trying to obtain push_user: '{c_u}' token for external push script"
                                   f", token will not be provided.\n{exc}")
                else:
                    def _versiontuple(v):
                        # https://stackoverflow.com/a/11887825/1361529
                        return tuple(map(int, (v.split("."))))

                    api_version = rj.get("apiversion")
                    if _versiontuple(api_version) >= _versiontuple("2.0"):
                        g.logger.debug(
                            2,
                            f"custom push script: detected API ver 2.0+, grabbing AUTH JWT for configured push_user"
                            f" '{c_u}'",
                        )
                        push_zm_tkn = rj.get("access_token")
                        push_zm_tkn = f"token={push_zm_tkn}"
                    else:
                        g.logger.debug(
                            2,
                            f"custom push script: Token auth is not setup on your ZM host, no access token "
                            f"will be provided to the custom push script '"
                            f"{Path(g.config.get('custom_push_script')).name}'"
                        )
                # gotify run using subshell or python requsts
                # fixme: URL clickable isn't working, using user&pass doesnt work only token does
                # c_pw = urllib.parse.quote(g.config.get("push_pass"), safe="")
                # use user&pass if using a specific user for pushover notifications otherwise use api auth
                # (token if API 2.0 else user and pass) should be using https
                if not push_zm_tkn:
                    push_zm_tkn = g.api.get_auth()
                # print(f"TOKEN FOR CUSTOM SCRIPT -> {push_zm_tkn}")

                try:
                    # requests method
                    # goti_host = g.config.get('gotify_host')
                    # goti_tkn = g.config.get('gotify_token')
                    # print(f"GOTIFY HOST -> {goti_host} -- {goti_tkn=}")
                    # data = {
                    #     "title": f"Camera: {g.config.get('mon_name')} - Event: {g.eid}",
                    #     "message": f"{pred_out}\n\n ![Camera Image]({g.api.portal_url}/index.php?view=image&eid={g.eid}&fid=objdetect&popup=1&{push_zm_tkn})",
                    #     "priority": 6,
                    #     "extras": {
                    #        "client::display": { "contentType": "text/markdown" },
                    #             "client::notification": { "click": {
                    #                     "url": f"{g.api.portal_url}/cgi-bin/nph-zms?mode=jpeg&frame=1&replay=none&source=event&event={g.eid}&{push_zm_tkn}"
                    #                 }
                    #             }
                    #     }
                    # }
                    # resp = requests.post(f'{goti_host}/message?token={goti_tkn}', json=data)
                    # shell script method
                    from shutil import which
                    custom_success = subprocess.check_output(
                        [
                            which('bash'),
                            g.config.get("custom_push_script"),
                            str(g.eid).strip("'").strip('"'),
                            repr(g.mid),
                            g.config.get('mon_name'),
                            new_notes,
                            et,
                            f"{push_zm_tkn}",
                            args.get('eventpath'),

                        ]
                    ).decode("ascii")
                except Exception as all_ex:
                    g.logger.error(f"{lp} ERROR while executing the custom push script "
                                   f"{g.config.get('custom_push_script')} -> \n{all_ex}")
                else:
                    # g.logger.debug(f"{lp} response from gotify -> {resp.status_code} - {resp.json()}")
                    # g.logger.debug(f"{lp} custom shell script returned -> {custom_success}")
                    if str(custom_success).strip() == '0':
                        g.logger.debug(f"{lp} custom push script returned SUCCESS")
                    else:
                        g.logger.debug(f"{lp} custom push script returned FAILURE")

            if str2bool(g.config.get("save_image_train")):
                train_dir = g.config.get(
                    "save_image_train_dir", f"{g.config.get('base_data_path')}/images"
                )
                if Path(train_dir).is_dir():
                    filename_training = f"{train_dir}/{g.eid}-training-frame-{_frame_id}.jpg"
                    filename_train_obj_det = f"{train_dir}/{g.eid}-compare-frame-{_frame_id}.jpg"
                    write_compare = False
                    if filename_training:
                        train_file = Path(filename_training)
                        if not train_file.exists():
                            g.logger.debug(
                                2,
                                f"{lp} saving ML model training and compare images to: '{train_dir}'",
                            )
                            write_compare = True
                        elif train_file.exists() and objdet_force:
                            g.logger.debug(
                                2,
                                f"{lp}{'FORCE:' if past_event else ''} frame ID: {_frame_id} from "
                                f"'Event': {g.eid} - saving ML model training and compare images to: '{train_dir}'"
                            )
                            write_compare = True

                        if write_compare:
                            try:
                                cv2.imwrite(filename_training, matched_data["image"])
                                cv2.imwrite(filename_train_obj_det, objdetect_jpeg_image)
                            except Exception as all_ex:
                                g.logger.error(
                                    f"{lp} writing {filename_training} and {filename_train_obj_det} "
                                    f"\nerr_msg -> {all_ex}"
                                )
                        else:
                            g.logger.debug(
                                2,
                                f"{lp} {filename_training}"
                                f"{' and {}'.format(filename_train_obj_det) if Path(filename_train_obj_det).exists() else ''} "
                                f" already exists, skipping writing....",
                            )
                elif not Path(train_dir).exists():
                    g.logger.error(
                        f"{lp}training images: the directory '{train_dir}' does not exist! "
                        f"can't save the model training and compare images! Please re-configure..."
                    )
                elif not Path(train_dir).is_dir():
                    g.logger.error(
                        f"{lp}training images: the directory '{train_dir}' exists but it is not a directory! "
                        f"can't save the model training and compare images! Please re-configure..."
                    )
            # ---------------------------------------------------------------
            # if we didn't write a new object detect image then theres no point doing all this, UNLESS we force it.
            # ---------------------------------------------------------------
            if wrote_objdetect or (not wrote_objdetect and objdet_force):
                # only update notes if its a past event or --notes was passed
                if old_notes and (past_event or args.get("notes")):

                    if new_notes != old_notes:
                        try:
                            events_url = f"{g.api.api_url}/events/{g.eid}.json"
                            g.api.make_request(
                                url=events_url,
                                payload={"Event[Notes]": new_notes},
                                type_action="put",
                                # quiet=True,
                            )
                        except Exception as all_ex:
                            g.logger.error(
                                f"{lp} error during notes update API put request-> {str(all_ex)}"
                            )
                        else:
                            g.logger.debug(
                                f"{lp} replaced old note -> '{old_notes}' with new note -> '{new_notes}'",
                            )
                    else:
                        g.logger.debug(
                            f"{lp} {'PAST EVENT ->' if past_event else ''} new notes are the same as old notes"
                            f" -> {new_notes}"
                        )

                if (
                        str2bool(g.config.get("create_animation"))
                        and
                        (
                                (past_event and objdet_force)
                                or (not past_event)
                        )
                ):
                    if bg_animations and bg_animations.is_alive():
                        g.logger.debug(
                            f"{lp}animation: waiting for animation creation thread to complete before "
                            f"we can send a pushover notification with the animation..."
                        )
                        # wait for the bg animations thread to create, optimize and save animations to disk.
                        bg_animations.join()

                    if (
                            send_push
                            and str2bool(g.config.get("push_enable"))
                            and Path(f"{args.get('eventpath')}/objdetect.gif").is_file()
                    ):

                        param_dict["device"] = (
                            g.config.get("push_debug_device")
                            if past_event
                            else param_dict.get("device")
                        )
                        param_dict[
                            "message"
                        ] = (
                            f"{pred_out.strip()} Sent to pushover servers @ "
                            f"{datetime.now().strftime('%H:%M:%S.%f')[:-3]}"
                        )
                        display_param_dict = param_dict.copy()
                        if g.config.get("push_gif"):
                            param_dict["token"] = g.config.get("push_gif")
                            display_param_dict["token"] = "<push_gif token>"
                        else:
                            param_dict["token"] = g.config.get("push_token")
                            display_param_dict["token"] = "<push_token token>"
                        if g.config.get("push_gif_key"):
                            param_dict["user"] = g.config.get("push_gif_key")
                            display_param_dict["user"] = "<push_gif_key user key>"
                        else:
                            param_dict["user"] = g.config.get("push_key")
                            display_param_dict["user"] = "<push_key user key>"

                        if matched_data.get("labels"):
                            # todo: Create a way to make custom sound groups
                            vehicles = ('truck', 'car', 'motorbike', 'bus')
                            # priority is in descending order
                            labels = tuple(matched_data.get("labels"))
                            if 'person' in labels and g.config.get('push_sound_person'):
                                param_dict['sound'] = g.config['push_sound_person']
                            elif any(w in vehicles for w in labels) and g.config.get('push_sound_vehicle'):
                                param_dict['sound'] = g.config['push_sound_vehicle']
                            elif 'car' in labels:
                                pass
                            elif 'truck' in labels:
                                pass
                            elif 'motorbike' in labels:
                                pass
                            elif 'dog' in labels:
                                pass
                            elif 'cat' in labels:
                                pass
                        # -----------------------------------------------------------
                        display_auth = (
                            f"user={g.config['sanitize_str']}&pass={g.config['sanitize_str']}"
                            if c_u and c_pw
                            else f"{'<api 2.0+ auth token>' if not g.config.get('basic_user') else '<basic credentials>'}"
                        )
                        display_url = (
                            f"{g.config.get('portal') if not str2bool(g.config.get('sanitize_logs')) else '{}'.format(g.config['sanitize_str'])}"
                            f"/cgi-bin/nph-zms?mode=jpeg&scale=50&maxfps=15&buffer=1000&replay=single&"
                            f"monitor={g.mid}&event={g.eid}&{display_auth}"
                        )
                        display_param_dict["url"] = display_url
                        files = {
                            "attachment": (
                                f"objdetect-{g.mid}.gif",
                                open(f"{args.get('eventpath')}/objdetect.gif", "rb"),
                                "image/jpeg",
                            )
                        }

                        g.logger.debug(
                            f"{lp}pushover:gif: data={display_param_dict} files=<'objdetect-{g.mid}.gif'>")
                        rl = False if past_event else True
                        bg_pushover_gif = Thread(
                            target=pushover.send,
                            kwargs={
                                "param_dict": param_dict,
                                "files": files,
                                "record_last": rl,
                            },
                        )
                        bg_pushover_gif.start()

        # TODO: split up like pushover to send jpg first then gif, so its fast
        #  also add ability to pass an image instead of it just looking for objdetect.jpg or .gif on disk
        if str2bool(g.config.get("mqtt_enable")) and (
                not past_event or (past_event and str2bool(g.config.get("mqtt_force")))
        ):
            bg_mqtt = Thread(
                target=do_mqtt,
                args=[
                    args,
                    et,
                    pred,
                    pred_out,
                    notes_zone,
                    matched_data,
                    objdetect_jpeg_image,
                    g,
                ],
            )
            bg_mqtt.start()

    else:
        g.logger.debug(f"{lp} no predictions returned from detections")
    detection_time: Optional[time.perf_counter] = None
    if start_of_remote_detection and start_of_local_fallback_detection:
        detection_time = start_of_local_fallback_detection
    elif start_of_remote_detection and not start_of_local_fallback_detection:
        detection_time = start_of_remote_detection
    elif start_of_local_detection:
        detection_time = start_of_local_detection
    fid_str_ = "-->'Frame ID':"
    fid_evtype = "'PAST' event" if past_event else "'LIVE' event"
    _mon_name = f"'Monitor': {g.Monitor.get('Name')} ({g.mid})->'Event': "
    final_msg = "perf:{lp}FINAL: {mid}{s}{f_id} [{match}] {tot}{before}{det}{ani_gif}{extras}".format(
        lp=lp,
        match="{}".format(fid_evtype if not args.get('file') else "INPUT FILE"),
        mid="{}".format(_mon_name) if not args.get("file") else "",
        s=g.eid,
        f_id="{}{}".format(fid_str_ if _frame_id and not args.get('file') else '',
                           f'{_frame_id if _frame_id and not args.get("file") else ""}'),
        tot=f"[total:{time.perf_counter() - start_of_script}] " if start_of_script else "",
        before=f"[pre detection:{total_time_start_to_detect}]" if total_time_start_to_detect else "",
        det=f"[detection:{detection_time}] " if detection_time else "",
        ani_gif="{}".format(
            "[processing {}".format(
                f"image/animation:{g.animation_seconds}] "
                if str2bool(g.config.get("create_animation"))
                else f"image:{g.animation_seconds}] "
            )
        )
        if g.animation_seconds
        else "",
        extras=f"[after detection: {time.perf_counter() - start_of_after_detection}] "
        if start_of_after_detection
        else "",
    )

    if bg_pushover_jpg and bg_pushover_jpg.is_alive():
        g.logger.debug(f"{lp} waiting for the JPEG pushover thread to finish")
        bg_pushover_jpg.join()
    if bg_pushover_gif and bg_pushover_gif.is_alive():
        g.logger.debug(f"{lp} waiting for the GIF pushover thread to finish")
        bg_pushover_gif.join()
    if bg_animations and bg_animations.is_alive():
        g.logger.debug(
            f"{lp} waiting for the Animation Creation thread to finish"
        )
        bg_animations.join()

    if bg_mqtt and bg_mqtt.is_alive():
        bg_mqtt.join()
    return final_msg, g


if __name__ == "__main__":
    try:
        output_message, g = main_handler()
    except Exception as e:
        print(f"zmes: err_msg->{e}")
        print(f"zmes: traceback: {format_exc()}")
    else:
        g.logger.debug(output_message) if output_message else None
        g.logger.log_close()
