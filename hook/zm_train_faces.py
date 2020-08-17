#!/usr/bin/python3
import argparse
import ssl
import pyzm.ZMLog as log 
import zmes_hook_helpers.common_params as g
import zmes_hook_helpers.utils as utils

if __name__ == "__main__":
    log.init(name='zm_train_faces', override={'dump_console':True})
# needs to be after log init

import pyzm.ml.face_train as train

if __name__ == "__main__":
    g.ctx = ssl.create_default_context()
    ap = argparse.ArgumentParser()
    ap.add_argument('-c',
                    '--config',
                    default='/etc/zm/objectconfig.ini',
                    help='config file with path')

    args, u = ap.parse_known_args()
    args = vars(args)

    #log.init(name='zm_face_train', dump_console=True)
    g.logger = log
    utils.process_config(args, g.ctx)
    train.FaceTrain(options=g.config).train()
