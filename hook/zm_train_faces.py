#!/usr/bin/python3
import zmes_hook_helpers.face_train as train
import argparse
import ssl
import zmes_hook_helpers.log as log
import zmes_hook_helpers.common_params as g
import zmes_hook_helpers.utils as utils

if __name__ == "__main__":
    log.init(process_name='zm_train_faces', dump_console=True)
# needs to be after log init

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
