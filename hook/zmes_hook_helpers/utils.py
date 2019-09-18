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
import json
import time

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
    return [map(int, x.strip().split(',')) for x in str.split(' ')]


def str_split(my_str):
    return [x.strip() for x in my_str.split(',')]


# Imports zone definitions from ZM
def import_zm_zones(mid):
    url = g.config['portal'] + '/api/zones/forMonitor/' + mid + '.json'
    g.logger.debug('Getting ZM zones using {}?user=xxx&pass=yyy'.format(url))
    url = url + '?user=' + g.config['user']
    url = url + '&pass=' + g.config['password']

    if g.config['portal'].lower().startswith('https://'):
        main_handler = urllib.request.HTTPSHandler(context=g.ctx)
    else:
        main_handler = urllib.request.HTTPHandler()

    if g.config['basic_user']:
        g.logger.debug('Basic auth config found, associating handlers')
        password_mgr = urllib.request.HTTPPasswordMgrWithDefaultRealm()
        top_level_url = g.config['portal']
        password_mgr.add_password(None, top_level_url, g.config['basic_user'], g.config['basic_password'])
        handler = urllib.request.HTTPBasicAuthHandler(password_mgr)
        opener = urllib.request.build_opener(handler, main_handler)

    else:
        opener = urllib.request.build_opener(main_handler)
    try:
        input_file = opener.open(url)
    except HTTPError as e:
        g.logger.error(e)
        raise

    c = input_file.read()
    j = json.loads(c)
    for item in j['zones']:
        g.polygons.append({'name': item['Zone']['Name'], 
                           'value': str2tuple(item['Zone']['Coords'])})
        g.logger.debug('importing zoneminder polygon: {} [{}]'
                       .format(item['Zone']['Name'], item['Zone']['Coords'])) 


# downloaded ZM image files for future analysis
def download_files(args):
    if g.config['wait'] > 0:
        g.logger.info ('Sleeping for {} seconds before downloading'.format(g.config['wait']))
        time.sleep(g.config['wait'])

    if g.config['portal'].lower().startswith('https://'):
        main_handler = urllib.request.HTTPSHandler(context=g.ctx)
    else:
        main_handler = urllib.request.HTTPHandler()

    if g.config['basic_user']:
        g.logger.debug('Basic auth config found, associating handlers')
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
        filename1_bbox = g.config['image_path'] + '/' + args['eventid'] + '-alarm-bbox.jpg'
        filename2 = g.config['image_path'] + '/' + args['eventid'] + '-snapshot.jpg'
        filename2_bbox = g.config['image_path'] + '/' + args['eventid'] + '-snapshot-bbox.jpg'

        url = g.config['portal'] + '/index.php?view=image&eid=' + args['eventid'] + '&fid=alarm' 
        durl = g.config['portal'] + '/index.php?view=image&eid=' + args['eventid'] + '&fid=alarm' 
        if g.config['user']:
            url = url + '&username=' + g.config['user'] + '&password=' + urllib.parse.quote(g.config['password'],safe='')
            durl = durl + '&username=' + g.config['user'] + '&password=*****'

        g.logger.debug('Trying to download {}'.format(durl))
        try:
            input_file = opener.open(url)
        except HTTPError as e:
            g.logger.error(e)
            raise
        with open(filename1, 'wb') as output_file:
            output_file.write(input_file.read())

        url = g.config['portal'] + '/index.php?view=image&eid=' + args['eventid'] + '&fid=snapshot' 
        durl = g.config['portal'] + '/index.php?view=image&eid=' + args['eventid'] + '&fid=snapshot' 
        if g.config['user']:
            url = url + '&username=' + g.config['user'] + '&password=' + urllib.parse.quote(g.config['password'],safe='')
            durl = durl + '&username=' + g.config['user'] + '&password=*****'
        g.logger.debug('Trying to download {}'.format(durl))
        try:
            input_file = opener.open(url)
        except HTTPError as e:
            g.logger.error(e)
            raise
        with open(filename2, 'wb') as output_file:
            output_file.write(input_file.read())

    else:
        # only download one
        filename1 = g.config['image_path'] + '/' + args['eventid'] + '.jpg'
        filename1_bbox = g.config['image_path'] + '/' + args['eventid'] + '-bbox.jpg'
        filename2 = None
        filename2_bbox = None

        url = g.config['portal'] + '/index.php?view=image&eid=' + args['eventid'] + '&fid=' + g.config['frame_id'] 
        durl = g.config['portal'] + '/index.php?view=image&eid=' + args['eventid'] + '&fid=' + g.config['frame_id'] 
        if g.config['user']:
            url = url + '&username=' + g.config['user'] + '&password=' + urllib.parse.quote(g.config['password'],safe='')
            durl = durl + '&username=' + g.config['user'] + '&password=*****'
        g.logger.debug('Trying to download {}'.format(durl))
        input_file = opener.open(url)
        with open(filename1, 'wb') as output_file:
            output_file.write(input_file.read())

    return filename1, filename2, filename1_bbox, filename2_bbox



def process_config(args, ctx):
# parse config file into a dictionary with defaults

    g.config = {}


    def _correct_type(val,t):
        if t == 'int':
             return int(val)
        elif t == 'eval':
            return eval(val) if val else None
        elif t == 'str_split':
            return str_split(val) if val else None
        elif t  == 'string':
            return val
        elif t == 'float':
            return float(val)
        else:
            g.logger.error ('Unknown conversion type {} for config key:{}'.format(e['type'], e['key']))
            return val

    def _set_config_val(k,v):
    # internal function to parse all keys
        val = config_file[v['section']].get(k,v['default'])
        g.config[k] = _correct_type(val, v['type'])
        if k.find('password') == -1:
            dval = g.config[k]
        else:
            dval = '***********'
        #g.logger.debug ('Config: setting {} to {}'.format(k,dval))

    # main        
    try:
        config_file = ConfigParser(interpolation=None)
        config_file.read(args['config'])
        # now read config values
        for k,v in g.config_vals.items():
            #g.logger.debug ('processing {} {}'.format(k,v))
            _set_config_val(k,v)
            #g.logger.debug ("done")
        
        
        if g.config['allow_self_signed'] == 'yes':
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            g.logger.debug('allowing self-signed certs to work...')
        else:
            g.logger.debug('strict SSL cert checking is on...')

        g.polygons = []

        # Check if we have a custom overrides for this monitor
        if args['monitorid']:
            sec = 'monitor-{}'.format(args['monitorid'])
            if sec in config_file: 
                # we have a specific section for this monitor
                for item in config_file[sec].items():
                    k = item[0]
                    v = item[1]
                    if k in g.config_vals:
                        # This means its a legit config key that needs to be overriden
                        g.logger.debug('[{}] overrides key:{} with value:{}'.format(sec, k,v))
                        g.config[k] = _correct_type(v, g.config_vals[k]['type'])
                    else:
                        # This means its a polygon for the monitor
                        g.polygons.append({'name': k, 'value': str2tuple(v)})
                        g.logger.debug('adding polygon: {} [{}]'.format(k, v))

                # now import zones if needed
                if g.config['import_zm_zones'] == 'yes':
                    import_zm_zones(args['monitorid'])
                    
           
        else:
            g.logger.info('Ignoring monitor specific settings, as you did not provide a monitor id')
    except Exception as e:
        g.logger.error('Error parsing config:{}'.format(args['config']))
        g.logger.error('Error was:{}'.format(e))
        exit(0)




