# utility functions that are not generic to a specific model

# includes idiotic shenanigans to make things work in Python2 and Python3:
# https://python-future.org/compatible_idioms.html


from __future__ import division
import logging
import logging.handlers
import sys
import datetime
import ssl
import urllib

from configparser import ConfigParser
import zmes_hook_helpers.common_params as g

from future import standard_library
standard_library.install_aliases()
from urllib.error import HTTPError

#resize polygons based on analysis scale
def rescale_polygons(xfactor, yfactor):
    newps = []
    for p in g.polygons:
        newp = []
        for x, y in p['value']:
            newx = int(x * xfactor)
            newy = int(y * yfactor)
            newp.append((newx, newy))
        newps.append({'name': p['name'], 'value': newp})
    g.logger.debug('resized polygons x={}/y={}: {}'.format(xfactor, yfactor, newps))
    g.polygons = newps

# converts a string of cordinates 'x1,y1 x2,y2 ...' to a tuple set. We use this
# to parse the polygon parameters in the ini file
def str2tuple(str):
    return [tuple(map(int, x.strip().split(','))) for x in str.split(' ')]

def str2arr(str):
    return  [map(int,x.strip().split(',')) for x in str.split(' ')]

def download_files(args):
    if g.config['portal'].lower().startswith('https://'):
        main_handler = urllib.request.HTTPSHandler(context=g.ctx)
    else:
        main_handler = urllib.request.HTTPHandler()


    if g.config['basic_user']:
        g.logger.debug ('Basic auth config found, associating handlers')
        password_mgr = urllib.request.HTTPPasswordMgrWithDefaultRealm()
        top_level_url = g.config['portal']
        password_mgr.add_password(None, top_level_url, g.config['basic_user'], g.config['basic_password'])
        handler = urllib.request.HTTPBasicAuthHandler(password_mgr)
        opener = urllib.request.build_opener(handler, main_handler)

    else:
        opener = urllib.request.build_opener(main_handler)

    if g.config['frame_id'] == 'bestmatch':
        # download both alarm and snapshot
        filename1 = g.config['image_path'] + '/' + args['eventid'] + '-alarm.jpg'
        filename2 = g.config['image_path'] + '/' + args['eventid'] + '-snapshot.jpg'
        url = g.config['portal'] + '/index.php?view=image&eid=' + args['eventid'] + '&fid=alarm' + \
            '&username=' + g.config['user'] + '&password=' + g.config['password']
        durl = g.config['portal'] + '/index.php?view=image&eid=' + args['eventid'] + '&fid=snapshot' + \
            '&username=' + g.config['user'] + '&password=*****'

        g.logger.debug('Trying to download {}'.format(durl))
        input_file= opener.open(url)
        with open (filename1, 'wb') as output_file:
            output_file.write(input_file.read())

        url = g.config['portal'] + '/index.php?view=image&eid=' + args['eventid'] + '&fid=snapshot' + \
            '&username=' + g.config['user'] + '&password=' + g.config['password']
        durl = g.config['portal'] + '/index.php?view=image&eid=' + args['eventid'] + '&fid=snapshot' + \
            '&username=' + g.config['user'] + '&password=*****'
        g.logger.debug('Trying to download {}'.format(durl))
        input_file= opener.open(url)
        with open (filename2, 'wb') as output_file:
            output_file.write(input_file.read())

    else:
        # only download one
        filename1 = g.config['image_path'] + '/' + args['eventid'] + '.jpg'
        filename2 = ''
        url = g.config['portal'] + '/index.php?view=image&eid=' + args['eventid'] + '&fid=' + g.config['frame_id'] + \
            '&username=' + g.config['user'] + '&password=' + g.config['password']
        durl = g.config['portal'] + '/index.php?view=image&eid=' + args['eventid'] + '&fid=snapshot' + \
            '&username=' + g.config['user'] + '&password=*****'
        g.logger.debug('Trying to download {}'.format(durl))
        input_file= opener.open(url)
        with open (filename1, 'wb') as output_file:
            output_file.write(input_file.read())
    return filename1, filename2


def process_config(args, ctx):
# parse config file into a dictionary with defaults

    g.config = {}
    try:
        config_file = ConfigParser()
        config_file.read(args['config'])
        g.config['portal'] = config_file['general'].get('portal', '')
        g.config['user'] = config_file['general'].get('user', 'admin')
        g.config['password'] = config_file['general'].get('password', 'admin')
        g.config['basic_user'] = config_file['general'].get('basic_user', '')
        g.config['basic_password'] = config_file['general'].get('basic_password', '')
        g.config['image_path'] = config_file['general'].get('image_path', '/var/lib/zmeventnotification/images')
        g.config['detect_pattern'] = config_file['general'].get('detect_pattern', '.*')
        g.config['frame_id'] = config_file['general'].get('frame_id', 'snapshot')
        g.config['resize'] = config_file['general'].get('resize', '800')
        g.config['delete_after_analyze'] = config_file['general'].get('delete_after_analyze', 'no')
        g.config['show_percent'] = config_file['general'].get('show_percent', 'no')
        g.config['log_level'] = config_file['general'].get('log_level', 'info')
        g.config['allow_self_signed'] = config_file['general'].get('allow_self_signed', 'yes')
        g.config['write_bounding_boxes'] = config_file['general'].get('write_bounding_boxes', 'yes')

        g.config['config'] = config_file['yolo'].get('yolo', '/var/lib/zmeventnotification/models/yolov3/yolov3.cfg')
        g.config['weights'] = config_file['yolo'].get('yolo', '/var/lib/zmeventnotification/models/yolov3/yolov3.weights')
        g.config['labels'] = config_file['yolo'].get('yolo', '/var/lib/zmeventnotification/models/yolov3/yolov3_classes.txt')
        g.config['poly_color'] = eval(config_file['yolo'].get('poly_color', '(127, 140, 141)'))

        g.config['stride']=eval(config_file['hog'].get('stride','(4,4)'));
        g.config['padding']=eval(config_file['hog'].get('padding','(8,8)'));
        g.config['scale']=config_file['hog'].get('scale','1.05');
        g.config['mean_shift']=config_file['hog'].get('mean_shift','-1');

        if g.config['log_level'] == 'debug':
            g.logger.setLevel(logging.DEBUG)
        elif g.config['log_level'] == 'info':
            g.logger.setLevel(logging.INFO)
        elif g.config['log_level'] == 'error':
            g.logger.setLevel(logging.ERROR)

        if g.config['allow_self_signed'] == 'yes':
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            g.logger.debug('allowing self-signed certs to work...')
        else:
            g.logger.debug('strict SSL cert checking is on...')

        # Check if we have a custom detection pattern for the current monitor
        if args['monitorid']:
            if config_file.has_option('monitor-%s' % args['monitorid'], 'detect_pattern'):
                # local detect_pattern overrides global
                g.config['detect_pattern'] = config_file['monitor-%s' % args['monitorid']].get('detect_pattern', '.*')
                g.logger.debug('monitor with ID {} has specific detection pattern: {}'.format(args['monitorid'], g.config['detect_pattern']))


        # get the polygons, if any, for the supplied monitor
        g.polygons = []
        if args['monitorid']:
            if config_file.has_section('monitor-' + args['monitorid']):
                itms = config_file['monitor-' + args['monitorid']].items()
                if itms:
                    g.logger.debug('object areas definition found for monitor:{}'.format(args['monitorid']))
                else:
                    g.logger.debug('object areas section found, but no polygon entries found')
                for k, v in itms:
                    if k == 'detect_pattern':
                        continue
                    g.polygons.append({'name': k, 'value': str2tuple(v)})
                    g.logger.debug('adding polygon: {} [{}]'.format(k, v))
            else:
                g.logger.debug('no object areas found for monitor:{}'.format(args['monitorid']))
        else:
            g.logger.info('Ignoring object areas, as you did not provide a monitor id')
    except Exception as e:
        g.logger.error('Error parsing config:{}'.format(args['config']))
        g.logger.error('Error was:{}'.format(e))
        exit(0)
        



