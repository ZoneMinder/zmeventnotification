#!/usr/bin/python3
import argparse
import ssl
import zm_ml.log as log
import zm_ml.common_params as g
import zm_ml.utils as utils

if __name__ == "__main__":
    log.init(process_name='zm_train_faces', dump_console=True)
# needs to be after log init

import zm_ml.face_train as train

if __name__ == "__main__":
    g.ctx = ssl.create_default_context()
    ap = argparse.ArgumentParser()
    ap.add_argument('-c',
                    '--config',
                    default='/etc/zm/objectconfig.ini',
                    help='config file with path')

    args, u = ap.parse_known_args()
    args = vars(args)

    utils.process_config(args, g.ctx)
    train.train()
