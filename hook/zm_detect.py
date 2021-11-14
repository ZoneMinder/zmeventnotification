#!/usr/bin/env python3
import copy
import json
import os
import signal
import subprocess
import sys
import time
import urllib.parse
from argparse import ArgumentParser
from ast import literal_eval
from datetime import datetime
from inspect import getframeinfo
from io import BytesIO
from pathlib import Path
from re import findall
from threading import Thread
from traceback import format_exc
from typing import Optional

import cv2
import numpy as np
import requests
import urllib3
# BytesIO and Image for saving images to bytes buffer
from PIL import Image

import pyzm.api
import pyzm.helpers.globals as gl
from pyzm import __version__ as pyzm_version
from pyzm.helpers.new_yaml import create_api, start_logs
from pyzm.helpers.pyzm_utils import (
    resize_image,
    write_text,
    pretty_print,
    draw_bbox,
    my_stdout,
    verify_vals,
    grab_frameid,
    str2bool,
    do_mqtt,
    do_hass
)

g: gl = gl
lp: str = 'zmes:'
caller: Optional[getframeinfo] = None
auth_header: Optional[dict] = None
access_token: Optional[str] = None
final_msg: Optional[str] = None
weighted_routes: Optional[dict] = None
ml_routes: Optional[dict] = None
start_of_script: Optional[datetime] = None
start_of_remote_detection: Optional[datetime] = None
start_of_local_detection: Optional[datetime] = None
start_of_local_fallback_detection: Optional[datetime] = None
start_of_after_detection: Optional[datetime] = None
bg_animations: Optional[Thread] = None
bg_pushover_jpg: Optional[Thread] = None
bg_pushover_gif: Optional[Thread] = None
bg_mqtt: Optional[Thread] = None

__app_version__: str = "7.0.3"


def remote_login(user, password, ml_api_url: str, name: str = None):
    # todo move sending encrypted creds here so it can be threaded?
    global auth_header, access_token
    lp = "zmes:mlapi:login:"
    # g.logger.info(f"{lp} '{g.api.api_url}'")
    ml_login_url = f"{ml_api_url}/login"
    _file_name = ml_api_url.lstrip('http://')
    show_route = f"{g.config.get('sanitize_str')}"
    # If there is a :port
    _file_name = _file_name.split(':')
    if len(_file_name) > 1:
        _file_name = _file_name[0]
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


def remote_detect(options=None, args=None):
    """Sends an http request to mlapi host with data needed for inference"""
    # This uses mlapi (https://github.com/baudneo/mlapi) to run inference with the sent data and converts format to
    # what is required by the rest of the code.
    global auth_header, access_token, weighted_routes, ml_routes, start_of_remote_detection
    lp = "zmes:mlapi:"
    # print(f"{g.eid = } {options = } {g.api = } {args =}")
    model = "object"  # default to object
    show_header = None
    show_route = f"{g.config.get('sanitize_str')}"
    files = {}
    # ml_routes integration, we know ml_enabled is True
    ml_routes = g.config.get('ml_routes')
    route: Optional[dict] = None
    if ml_routes:
        weighted_routes = None
        if isinstance(ml_routes, str):
            ml_routes = literal_eval(ml_routes)
        weighted_routes = sorted(ml_routes, key=lambda _route: _route['weight'])
        g.config['ml_routes'] = weighted_routes
        route = weighted_routes[0]
        g.config['ml_gateway'] = route['gateway']
        g.config['ml_user'] = route['user']
        g.config['ml_password'] = route['pass']

    ml_api_url = g.config.get('ml_gateway')
    g.logger.info(
        f"|----------= Encrypted Route Name: '{route['name']}' | Gateway URL: "
        f"'{ml_api_url if not str2bool(g.config.get('sanitize_logs')) else show_route}' | "
        f"Weight: {route['weight']} =----------|"
    )
    ml_object_url = f"{ml_api_url}/detect/object?type={model}"
    use_auth = True

    if not g.config.get("ml_user") and not g.config.get("ml_password"):
        use_auth = False
    if use_auth and not access_token:
        remote_login(g.config['ml_user'], g.config['ml_password'], g.config['ml_gateway'], name=route.get('name'))
        if not access_token:  # add a re login loop?
            raise ValueError("Can't obtain MLAPI AUTH JWT")
        auth_header = {"Authorization": f"Bearer {access_token}"}
        show_header = {"Authorization": f"{auth_header.get('Authorization')[:30]}......"}

    params = {"delete": True, "response_format": "zm_detect"}

    file_image = None
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
            succ, jpeg = cv2.imencode(".jpg", image)
            if not succ:
                g.logger.error(f"{lp} ERROR: cv2.imencode('.jpg', <FILE IMAGE>)")
                raise ValueError("--file Can't encode image on disk into jpeg")
            files = {
                "image": ("image.jpg", jpeg.tobytes(), 'application/octet')
            }

    # ml-overrides grabs the default value for these patterns because their actual values are held in g.config
    # we can send these now and enforce them? but if using mlapi should mlapiconfig.yml take precedence over
    # ml_overrides? model_sequence already overrides mlapi, so..... ???
    ml_overrides = {
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
    # Send PushOver notification on GPU/TPU failures with some info
    if str2bool(g.config.get("push_errors")):
        # Encrypt the app token and user key for transport
        sub_options = {
            "push_errors": g.config.get("push_errors"),
            "push_options": {
                "token": g.config.get("push_err_token", g.config.get("push_token")),
                "user": g.config.get("push_err_key", g.config.get("push_key")),
                "sound": g.config.get("push_sound"),
            },
        }
    else:
        sub_options = {
            "push_errors": 'no',
            "push_options": {
                "token": None,
                "user": None,
                "sound": None,
            },
        }
    # Get api creds ready
    encrypted_data = None
    try:
        from cryptography.fernet import Fernet
        # assign Fernet object to a variable
        f = Fernet
    except ImportError:
        g.logger.error(
            f"{lp} the cryptography library does not seem to be installed! Please install using -> "
            f"(sudo) pip3 install cryptography"
        )
        Fernet = None
        del Fernet
        # raise an exception to trigger the next route or local fallback
        raise ValueError(f"cryptography library not installed or accessible")
    else:
        encrypted_data = {}
        try:
            key: str = route['enc_key'].encode('utf-8')
            kickstart = g.api.cred_dump()
            # init the Fernet object with the key
            f = f(key)
        except Exception as exc:
            g.logger.error(
                f"{lp} it appears the encryption key provided is malformed! "
                f"check the encryption key in route '{route['name']}'"
            )
            # raise an exception to trigger the next route or local fallback
            raise ValueError(f"encryption key malformed for {route['name']}")
        auth_type = None
        # Encode into a byte string and encrypt using 'key'
        route_name = route['name'] or 'default_route'
        # Auth type and creds based on which type
        auth_type = g.api.auth_type

        if auth_type == 'token':
            kickstart['api_url'] = g.api.api_url
            kickstart['portal_url'] = g.api.portal_url
            for k, v in kickstart.items():
                if v:
                    encrypted_data[f.encrypt(str(k).encode('utf-8'))] = f.encrypt(str(v).encode('utf-8'))
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
    mlapi_json = {
        "version": __app_version__,
        "mid": g.mid,
        "reason": args.get("reason"),
        "stream": g.eid,
        "stream_options": options,
        "ml_overrides": ml_overrides,
        "sub_options": sub_options,
        "encrypted data": encrypted_data,
    }
    # files = {
    #     'document': (local_file_to_send, open(local_file_to_send, 'rb'), 'application/octet'),
    #     'datas' : ('datas', json.dumps(datas), 'application/json'),
    # }
    if files:
        # If we are sending a file we must add the JSON to the files dict HACK
        files['json'] = (json.dumps(mlapi_json))
    # ml_api_url if not str2bool(g.config.get('sanitize_logs')) else show_route
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
        r = requests.post(
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
        # g.logger.debug(f"traceback-> {format_exc()}")
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
                g.logger.debug(f"{lp} parsed the matched image from bytes to a jpeg encoded array in multipart response")
                img = part.content

            elif part.headers.get(b'Content-Type') == b'application/json':
                g.logger.debug(f"{lp} parsed JSON detection data in multipart response")
                data = json.loads(part.content.decode('utf-8'))
        if data.get('success'):
            # success only when there is an image
            try:
                img = np.frombuffer(img, dtype=np.uint8)
                img = cv2.imdecode(img, cv2.IMREAD_UNCHANGED)

            except Exception as exc:
                g.logger.error(f"{lp} the image in the response is malformed! -> \n{exc}")
                g.logger.error(format_exc())
            else:
                if img is not None and len(img.shape) <= 3:
                    # check if the image is already resized to the configured 'resize' value
                    if options.get("resize", 'no') != "no" and options.get('resize') != img.shape[1]:
                        img = resize_image(img, options.get("resize"))
                    data["matched_data"]["image"] = img
                else:
                    g.logger.fatal(f"{lp} mlapi replied with an image. "
                                   f"ZMES was unable to reconstruct the image. FATAL, exiting...")
        return data


def _parse_args():
    ap = ArgumentParser()
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
                    "--eventid",
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
        "--pdb", help="activate Python DeBugger breakpoints, beware this breaks autonomy", action="store_true"
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
    return args


def main_handler():
    from multiprocessing.pool import ThreadPool
    pool = ThreadPool(processes=1)
    global final_msg, g, start_of_local_detection, start_of_local_fallback_detection, \
        start_of_after_detection, start_of_remote_detection, start_of_script
    global bg_pushover_jpg, bg_pushover_gif, bg_animations, bg_mqtt
    # -------------- vars -------------------
    bg_api_thread: Optional[Thread] = None
    bg_logger: Optional[Thread] = None
    objdetect_jpeg_image: Optional[np.ndarray] = None
    (old_notes, notes_zone, notes_cause, prefix, pred, detections, seen) = ("", "", "", "", "", [], [],)
    remote_sanitized, ml_options, stream_options, obj_json = {}, {}, {}, []
    (m, matched_data, all_data, pushover, c_u,
     c_pw, bio, past_event, es_version, _frame_id) = (None, None, None, None, False, "(?)", None, None, None, None)
    # -------------- END vars -------------------
    # She's ugly but she works
    from pyzm.helpers.pyzm_utils import set_g
    set_g(g)
    # end of the disgusting
    lp = "zmes:"
    args = _parse_args()
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

    # process the config
    start_conf = datetime.now()
    g.eid = args.get("eventid", args.get("file"))
    from pyzm.helpers.new_yaml import process_config as proc_conf
    zmes_config, g = proc_conf(args=args, conf_globals=g, type_='zmes')
    g.logger.debug(f"perf:{lp} building the intial config took {(datetime.now()-start_conf).total_seconds()} ")

    bg_api_thread = Thread(target=create_api, kwargs={'args': args})
    start_api_create = datetime.now()
    bg_api_thread.start()
    objdet_force = str2bool(g.config.get("force_debug"))
    et = args.get("event_type")
    # Get zmeventnotification.pl VERSION
    try:
        from shutil import which
        es_version = subprocess.check_output(
            [which("zmeventnotification.pl"), "--version"]
        ).decode("ascii")
    except Exception as all_ex:
        g.logger.error(f"{lp} while grabbing zmeventnotification.pl VERSION -> {all_ex}")
        es_version = "Unknown"
        pass
    else:
        es_version = es_version.rstrip()
    g.logger.info(
        f"------|  FORKED NEO --- app->Hooks: {__app_version__} - pyzm: {pyzm_version} - ES: {es_version}"
        f" - OpenCV:{cv2.__version__} |------"
    )
    # misc came later, so lets be safe - Converted to Path()
    Path(f"{g.config['base_data_path']}/misc/").mkdir(exist_ok=True)
    # Monitor overrides (returns default config if there are no per monitor overrides)
    if args.get('live') and args.get('monitor_id'):
        g.logger.debug(f"{lp} Monitor ID provided by the ZMES Perl script, skipping monitor ID verification...")
        g.config['mid'] = g.mid = int(args["monitor_id"])
    if not g.mid:
        start_wait = datetime.now()
        g.logger.debug(f"{lp} waiting for the monitor ID to be verified! This happens on "
        f"PAST events because the api double checks to make sure its the correct monitor ID")
        while not g.mid:
            if (datetime.now() - start_wait).total_seconds() > 5.0:
                break
            time.sleep(0.033)
        if not g.mid:
            g.logger.debug(f"{lp} g.mid not populated! waited {(datetime.now() - start_wait).total_seconds()} seconds "
                           f"and nothing.... joining thread if its alive!")
            if bg_api_thread and bg_api_thread.is_alive():
                bg_api_thread.join()
            g.logger.debug(f"{lp} after waiting for g.mid and joining the api creation thread the total time for "
                           f"api creation is {(datetime.now() - start_api_create).total_seconds()} seconds")
        else:
            g.logger.debug(
                f"perf:{lp} Monitor ID ({g.mid}) verified! pausing to wait for verification took "
                f"{(datetime.now() - start_wait).total_seconds()} seconds -=- api creation took "
                f"{(datetime.now() - start_api_create).total_seconds()} seconds"
            )
    if not g.mid and not args.get('file'):
        msg = f"{lp} SOMETHING is very WRONG! EXITING"
        g.logger.debug(msg)
        print(msg)
        g.logger.log_close()
        exit(1)
    if g.mid and g.mid in zmes_config.monitors:
        # only need to build 1 override
        zmes_config.monitor_override(g.mid)
        # override the global config with the overrode per monitor config
        g.config = zmes_config.monitor_overrides[g.mid]
    else:
        g.config = zmes_config.config

    from pyzm.ZMLog import sig_intr, sig_log_rot
    g.logger.info(f"{lp} Setting up signal handlers for log 'rotation' and log 'interrupt'")
    signal.signal(signal.SIGHUP, sig_log_rot)
    signal.signal(signal.SIGINT, sig_intr)
    # async_result = pool.apply_async(
    #     start_logs,
    #     {
    #         'config': g.config,
    #         'args': args,
    #         '_type': 'zmes',
    #         'no_signal': True,
    #     }
    # )  # tuple of args for foo, dict for kwargs
    #
    # # do some other stuff in the main process
    # g.logger = async_result.get()  # get the return value from your function.
    bg_logger = Thread(target=start_logs, kwargs={'config': g.config, 'args': args, '_type': 'zmes', 'no_signal': True}).start()
    if str2bool(g.config["only_triggered_zm_zones"]):
        g.config["import_zm_zones"] = "yes"
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
    skip = g.config.get("skip_mons")
    skip = skip.split(",") if skip and isinstance(skip, str) else None
    if (
            skip and str(g.mid) in skip and args.get("live")
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
        remote_response = {}
        tries = 0
        max_tries = len(weighted_routes) + 2 if weighted_routes else 2
        start_of_remote_detection = datetime.now()
        while True and tries < max_tries:
            tries += 1
            if remote_response or matched_data:
                break
            try:
                if tries > 1:
                    if weighted_routes and len(weighted_routes) > 1:
                        g.logger.debug(f"{lp} there was an error, using the next weighted route")
                        weighted_routes.pop(0)
                        g.config['ml_routes'] = weighted_routes
                    elif str2bool(g.config.get('ml_fallback_local')):
                        start_of_local_fallback_detection = datetime.now()
                        g.logger.error(f"{lp} mlapi error, falling back to local detection")
                        stream_options["polygons"] = zmes_config.polygons.get(g.mid)
                        from pyzm.ml.detect_sequence import DetectSequence
                        m = DetectSequence(options=ml_options, globs=g)
                        sub_options = {
                            "push_errors": g.config.get("push_errors"),
                            "push_options": {
                                "token": g.config.get("push_err_token", g.config.get("push_token")),
                                "user": g.config.get("push_err_key", g.config.get("push_key")),
                                "sound": g.config.get("push_sound"),
                                # 'url': po_opts.get('url'),
                                # 'url_title': g.config.get('url_title'),
                                # 'priority': po_opts.get('priority'),
                                # 'device': po_opts.get('device'),
                            },
                        }
                        show_sub_option = {
                            "push_errors": g.config.get("push_errors"),
                            "push_options": {
                                "token": f"{g.config['sanitize_str']}",
                                "user": f"{g.config['sanitize_str']}",
                                "sound": g.config.get("push_error_sound"),
                            },
                        }
                        if bg_api_thread and bg_api_thread.is_alive():
                            g.logger.debug(
                                f"{lp} waiting for the ZM API Session to be created and authorized...")
                            bg_api_thread.join()
                        matched_data, all_data, all_frames = m.detect_stream(
                            stream=g.eid,
                            options=stream_options,
                            sub_options=sub_options,
                            in_file=True if args.get('file') else False
                        )
                        start_of_local_fallback_detection = (datetime.now()
                                                             - start_of_local_fallback_detection).total_seconds()
                        break
                    else:
                        break
                remote_response = remote_detect(options=stream_options, args=args)
            except requests.exceptions.HTTPError as http_ex:
                start_of_remote_detection = (datetime.now() - start_of_remote_detection).total_seconds()
                if http_ex.response.status_code == 400:
                    if args.get('file'):
                        g.logger.error(
                            f"{lp} ERR 400 -> there seems to be an error trying to send an image from "
                            f"zm_detect to mlapi, looking into it -> {http_ex.response.json()}"
                        )
                    else:
                        # todo: pushover error
                        g.logger.error(
                            f"{lp} ERR 400 -> {http_ex.response.json()}"
                        )
                if http_ex.response.status_code == 500:
                    # todo: pushover error
                    g.logger.error(
                        f"{lp} ERR 500 -> there seems to be an Internal Error with the mlapi host, check"
                        f" mlapi logs! -> {http_ex.response.json()}"
                    )
                else:
                    g.logger.debug(
                        f"{lp} ERR {http_ex.response.status_code} -> "
                        f"HTTP ERROR --> {http_ex.response.json()}"
                    )
            except ValueError as exc:
                start_of_remote_detection = (datetime.now() - start_of_remote_detection).total_seconds()
                if str(exc) == 'MLAPI remote detection error!':
                    # todo: pushover error
                    print(f"MLAPI remote detection error!")
                else:
                    print(exc)
                    raise exc
            except Exception as all_ex:
                start_of_remote_detection = (datetime.now() - start_of_remote_detection).total_seconds()
                print(f"{lp} there was an error during the remote detection! -> {all_ex}")
                print(format_exc())
            # Successful mlapi post
            else:
                start_of_remote_detection = (datetime.now() - start_of_remote_detection).total_seconds()
                if remote_response is not None:
                    matched_data = remote_response.get("matched_data")
                    all_data = remote_response["all_matches"]
                    remote_sanitized: dict = copy.deepcopy(remote_response)
                    remote_sanitized["matched_data"]["image"] = "<uint-8 encoded jpg>" if matched_data.get(
                        'image') is not None else "<No Image Returned>"
                mon_name = f"Monitor: {g.config.get('mon_name')} ({g.mid})->'Event': "
                g.logger.debug(
                    f"perf:{lp}mlapi: {f'{mon_name}' if not args.get('file') else ''}{g.eid}"
                    f" mlapi detection took: {start_of_remote_detection}"
                )
                break

    else:  # mlapi not configured, local detection
        start_of_local_detection = datetime.now()
        if not args.get("file") and float(g.config.get("wait", 0)) > 0.0:
            g.logger.info(
                f"{lp}local: sleeping for {g.config['wait']} seconds before running models"
            )
            time.sleep(float(g.config["wait"]))
        try:
            from pyzm.ml.detect_sequence import DetectSequence
            m = DetectSequence(options=g.config['ml_sequence'], globs=g)
            sub_options = {
                "push_errors": g.config.get("push_errors"),
                "push_options": {
                    "token": g.config.get("push_err_token", g.config.get("push_token")),
                    "user": g.config.get("push_err_key", g.config.get("push_key")),
                    "sound": g.config.get("push_sound"),
                    # 'url': po_opts.get('url'),
                    # 'url_title': g.config.get('url_title'),
                    # 'priority': po_opts.get('priority'),
                    # 'device': po_opts.get('device'),
                },
            }
            show_sub_option = {
                "push_errors": g.config.get("push_errors"),
                "push_options": {
                    "token": f"{g.config['sanitize_str']}",
                    "user": f"{g.config['sanitize_str']}",
                    "sound": g.config.get("push_error_sound"),
                },
            }
            if bg_api_thread and bg_api_thread.is_alive():
                g.logger.debug(f"{lp}local: waiting for the ZM API Session to be created and authorized...")
                bg_api_thread.join()
            matched_data, all_data, all_frames = m.detect_stream(
                stream=g.eid, options=stream_options, sub_options=sub_options,
                in_file=True if args.get('file') else False
            )
        except Exception as all_ex:
            # todo: pushover error
            g.logger.debug(f"{lp}local: TPU and GPU in ZM DETECT? --> {all_ex}")
        else:
            start_of_local_detection = (datetime.now() - start_of_local_detection).total_seconds()
            g.logger.debug(f"perf:{lp}local: detection took: {start_of_local_detection}")
    # Format the frame ID (if it contains s- for snapshot conversion)
    start_of_after_detection = datetime.now()
    if matched_data is not None:
        _frame_id = grab_frameid(matched_data.get("frame_id"))
        obj_json = {
            "frame_id": _frame_id,
            "labels": matched_data["labels"],
            "confidences": matched_data["confidences"],
            "boxes": matched_data["boxes"],
            "image_dimensions": matched_data["image_dimensions"],
        }
        # Print returned data nicely if there are any detections returned
        if len(matched_data.get("labels")):
            pretty_print(matched_data=matched_data, remote_sanitized=remote_sanitized)

        if matched_data["frame_id"] == "snapshot":
            prefix = "[s] "
        elif matched_data["frame_id"] == "alarm":
            prefix = "[a] "
        else:
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
        # switch stdout back to console so we can send the detection back to the perl script and the event wrapper
        # shell script
        if not args.get("debug"):
            sys.stdout = sys.__stdout__
        if not args.get('file') and not past_event:
            print(f"\n{pred_out.rstrip()}--SPLIT--{jos}\n")
        if not args.get("debug"):
            sys.stdout = my_stdout()

        if not g.api_event_response and not args.get('file'):
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
                if not g.api:
                    print(f"{lp} creating the api object, it isnt initialized yet")
                    create_api(args)
                if not g.api_event_response:
                    g.Event, g.Monitor, g.Frame = g.api.get_all_event_data()
                try:
                    from pyzm.helpers.pyzm_utils import createAnimation
                    # how long it takes to create the animations
                    g.animation_seconds = datetime.now()
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
                if ha_verified and str2bool(g.config.get("hass_enable")):
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
                    f"{lp} not writing objdetect.jpg or objects.json as monitor {g.mid}->'{args['mon_name']}' "
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
                            f"{pred_out.strip()} Sending to pushover servers @ "
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
        if bg_logger and bg_logger.is_alive():
            bg_logger.join(3)
        g.logger.debug(f"{lp} no predictions returned from detections")
    start_of_after_detection = (datetime.now() - start_of_after_detection).total_seconds()
    start_of_script = (datetime.now() - start_of_script).total_seconds()
    detection_time: Optional[datetime] = None
    if start_of_remote_detection and start_of_local_fallback_detection:
        detection_time = start_of_local_fallback_detection
    elif start_of_remote_detection and not start_of_local_fallback_detection:
        detection_time = start_of_remote_detection
    elif start_of_local_detection:
        detection_time = start_of_local_detection
    fid_str_ = "-->'Frame ID':"
    fid_evtype = "PAST event" if past_event else "LIVE event"
    _mon_name = f"'Monitor': {g.config.get('mon_name')} ({g.mid})->'Event': "
    final_msg = "perf:{lp}FINAL: {mid}{s}{f_id} [{match}] {tot}{det}{ani_gif}{extras}".format(
        lp=lp,
        match="{}".format(fid_evtype if not args.get('file') else "INPUT FILE"),
        mid="{}".format(_mon_name) if not args.get("file") else "",
        s=g.eid,
        f_id="{}{}".format(fid_str_ if _frame_id and not args.get('file') else '',
                           f'{_frame_id if _frame_id and not args.get("file") else ""}'),
        tot=f"[total:{start_of_script}] " if start_of_script else "",
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
        extras=f"[after core detection: {start_of_after_detection}] "
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


if __name__ == "__main__":
    start_of_script = datetime.now()
    try:
        from pyzm.helpers.pyzm_utils import LogBuffer

        g.logger = LogBuffer()
        main_handler()
    except Exception as e:
        if sys.stdout == sys.__stdout__:  # if stdout is set to system then print to console
            print(f"zmes: err_msg->{e}")
            print(f"zmes: traceback: {format_exc()}")
        else:  # otherwise stdout is outputting to the logger, print is hijacked
            g.logger.error(f"zmes: MAIN_HANDLER LOOP : err_msg->{e}")
            g.logger.debug(f"zmes: traceback: {format_exc()}")

    else:
        g.logger.debug(final_msg) if final_msg else None
        g.logger.log_close()
    finally:  # always hand it back to the system
        sys.stderr = sys.__stderr__
        sys.stdout = sys.__stdout__
