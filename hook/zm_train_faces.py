#!/usr/bin/python3
import argparse

from pyzm.helpers.pyzm_utils import LogBuffer, set_g
import pyzm.ml.face_train_dlib as train
from pyzm.helpers.new_yaml import process_config as proc_conf, start_logs
import pyzm.helpers.globals as g

set_g(g)
g.logger = LogBuffer()

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument('-c',
                    '--config',
                    default='/etc/zm/objectconfig.yml',
                    help='config file with path')

    ap.add_argument('-s',
                    '--size',
                    type=int,
                    help='resize amount (if you run out of memory)')
    ap.add_argument('-d', '--debug', help='enables debug on console', action='store_true')
    ap.add_argument('-bd', '--baredebug', help='enables debug on console', action='store_true')

    args, u = ap.parse_known_args()
    args = vars(args)
    if not args.get('debug') or args.get('baredebug'):
        args['debug'] = True
    args['from_face_train'] = True

    zmesc = proc_conf(args=args, conf_globals=g)
    # Monitor overrides (returns default config if there are no per monitor overrides)
    g.config = zmesc.config
    # start the logger (you can Thread this if you want)
    start_logs(config=g.config, args=args, _type='zmes')
    train.FaceTrain(globs=g).train(size=args['size'])




