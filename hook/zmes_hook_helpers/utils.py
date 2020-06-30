# utility functions that are not generic to a specific model


from __future__ import division
import logging
import logging.handlers
import sys
import datetime
import ssl
import urllib
import json
import time
import re
import ast
import urllib.parse
import traceback

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
    g.logger.debug('resized polygons x={}/y={}: {}'.format(
        xfactor, yfactor, newps),level=2)
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
def import_zm_zones(mid, reason):
    match_reason = True if g.config['only_triggered_zm_zones']=='yes' else False
    url = g.config['portal'] + '/api/zones/forMonitor/' + mid + '.json'
    g.logger.debug('Getting ZM zones using {}?username=xxx&password=yyy&user=xxx&pass=yyy'.format(url),level=2)
    url = url + '?username=' + g.config['user']
    url = url + '&password=' + urllib.parse.quote(g.config['password'], safe='')
    url = url + '&user=' + g.config['user']
    url = url + '&pass=' + urllib.parse.quote(g.config['password'], safe='')

    if g.config['portal'].lower().startswith('https://'):
        main_handler = urllib.request.HTTPSHandler(context=g.ctx)
    else:
        main_handler = urllib.request.HTTPHandler()

    if g.config['basic_user']:
        g.logger.debug('Basic auth config found, associating handlers',level=2)
        password_mgr = urllib.request.HTTPPasswordMgrWithDefaultRealm()
        top_level_url = g.config['portal']
        password_mgr.add_password(None, top_level_url, g.config['basic_user'],
                                  g.config['basic_password'])
        handler = urllib.request.HTTPBasicAuthHandler(password_mgr)
        opener = urllib.request.build_opener(handler, main_handler)

    else:
        opener = urllib.request.build_opener(main_handler)
    try:
        input_file = opener.open(url)
    except HTTPError as e:
        g.logger.error(f'HTTP Error in import_zm_zones:{e}')
        raise
    except Exception as e:
        g.logger.error(f'General error in import_zm_zones:{e}')
        raise

    c = input_file.read()
    j = json.loads(c)

    # Now lets look at reason to see if we need to 
    # honor ZM motion zones

    reason_zones = []
    if match_reason and reason and 'Motion:' in reason:
        rz = reason.split('Motion:')
        if len(rz) > 1:
            rz = rz[1]
            reason_zones = [x.strip() for x in rz.split(',')]
            g.logger.debug('Found motion zones provided in alarm cause: {}'.format(reason_zones))


    for item in j['zones']:
        if not match_reason or 'All' in reason_zones or item['Zone']['Name'] in reason_zones:
            g.polygons.append({
                'name': item['Zone']['Name'],
                'value': str2tuple(item['Zone']['Coords'])
            })
            g.logger.debug('importing zoneminder polygon: {} [{}]'.format(
                item['Zone']['Name'], item['Zone']['Coords']), level=2)
        else:
            g.logger.debug('dropping {} as zones in alarm cause is {}'.format(item['Zone']['Name'], reason_zones))


# downloaded ZM image files for future analysis
def download_files(args):
    if g.config['wait'] > 0:
        g.logger.info('Sleeping for {} seconds before downloading'.format(
            g.config['wait']))
        time.sleep(g.config['wait'])

    
    if g.config['portal'].lower().startswith('https://'):
        main_handler = urllib.request.HTTPSHandler(context=g.ctx)
    else:
        main_handler = urllib.request.HTTPHandler()

    if g.config['basic_user']:
        g.logger.debug('Basic auth config found, associating handlers',level=2)
        password_mgr = urllib.request.HTTPPasswordMgrWithDefaultRealm()
        top_level_url = g.config['portal']
        password_mgr.add_password(None, top_level_url, g.config['basic_user'],
                                  g.config['basic_password'])
        handler = urllib.request.HTTPBasicAuthHandler(password_mgr)
        opener = urllib.request.build_opener(handler, main_handler)

    else:
        opener = urllib.request.build_opener(main_handler)

    if g.config['frame_id'] == 'bestmatch':
        # download both alarm and snapshot
        filename1 = g.config['image_path'] + '/' + args.get(
            'eventid') + '-alarm.jpg'
        filename1_bbox = g.config['image_path'] + '/' + args.get(
            'eventid') + '-alarm-bbox.jpg'
        filename2 = g.config['image_path'] + '/' + args.get(
            'eventid') + '-snapshot.jpg'
        filename2_bbox = g.config['image_path'] + '/' + args.get(
            'eventid') + '-snapshot-bbox.jpg'

        url = g.config['portal'] + '/index.php?view=image&eid=' + args.get(
            'eventid')+ '&fid=alarm'
        durl = g.config['portal'] + '/index.php?view=image&eid=' + args.get(
            'eventid') + '&fid=alarm'
        if g.config['user']:
            url = url + '&username=' + g.config[
                'user'] + '&password=' + urllib.parse.quote(
                    g.config['password'], safe='')
            durl = durl + '&username=' + g.config['user'] + '&password=*****'

        g.logger.debug('Trying to download {}'.format(durl))
        try:
            input_file = opener.open(url)
        except HTTPError as e:
            g.logger.error(e)
            raise
        with open(filename1, 'wb') as output_file:
            output_file.write(input_file.read())
            output_file.close()

        url = g.config['portal'] + '/index.php?view=image&eid=' + args.get(
            'eventid') + '&fid=snapshot'
        durl = g.config['portal'] + '/index.php?view=image&eid=' + args.get(
            'eventid') + '&fid=snapshot'
        if g.config['user']:
            url = url + '&username=' + g.config[
                'user'] + '&password=' + urllib.parse.quote(
                    g.config['password'], safe='')
            durl = durl + '&username=' + g.config['user'] + '&password=*****'
        g.logger.debug('Trying to download {}'.format(durl))
        try:
            input_file = opener.open(url)
        except HTTPError as e:
            g.logger.error(e)
            raise
        with open(filename2, 'wb') as output_file:
            output_file.write(input_file.read())
            output_file.close()

    else:
        # only download one
        filename1 = g.config['image_path'] + '/' + args.get('eventid') + '.jpg'
        filename1_bbox = g.config['image_path'] + '/' + args.get(
            'eventid') + '-bbox.jpg'
        filename2 = None
        filename2_bbox = None

        url = g.config['portal'] + '/index.php?view=image&eid=' + args.get(
            'eventid') + '&fid=' + g.config['frame_id']
        durl = g.config['portal'] + '/index.php?view=image&eid=' + args.get(
            'eventid') + '&fid=' + g.config['frame_id']
        if g.config['user']:
            url = url + '&username=' + g.config[
                'user'] + '&password=' + urllib.parse.quote(
                    g.config['password'], safe='')
            durl = durl + '&username=' + g.config['user'] + '&password=*****'
        g.logger.debug('Trying to download {}'.format(durl))
        input_file = opener.open(url)
        with open(filename1, 'wb') as output_file:
            output_file.write(input_file.read())
            output_file.close()
    return filename1, filename2, filename1_bbox, filename2_bbox

def get_pyzm_config(args):
    g.config['pyzm_overrides'] = {}
    config_file = ConfigParser(interpolation=None)
    config_file.read(args.get('config'))
    if config_file.has_option('general', 'pyzm_overrides'):
        pyzm_overrides = config_file.get('general', 'pyzm_overrides')
        g.config['pyzm_overrides'] =  ast.literal_eval(pyzm_overrides) if pyzm_overrides else {}     


def process_config(args, ctx):
    # parse config file into a dictionary with defaults

    #g.config = {}
    has_secrets = False
    secrets_file = None

    def _correct_type(val, t):
        if t == 'int':
            return int(val)
        elif t == 'eval' or t == 'dict':
            return ast.literal_eval(val) if val else None
        elif t == 'str_split':
            return str_split(val) if val else None
        elif t == 'string':
            return val
        elif t == 'float':
            return float(val)
        else:
            g.logger.error(
                'Unknown conversion type {} for config key:{}'.format(
                    e['type'], e['key']))
            return val

    def _set_config_val(k, v):
        # internal function to parse all keys
        if config_file.has_section(v['section']):
            val = config_file[v['section']].get(k, v['default'])
        else:
            val = v['default']
            g.logger.debug(
                'Section [{}] missing in config file, using key:{} default: {}'
                .format(v['section'], k, val))

        if val and val[0] == '!':  # its a secret token, so replace
            g.logger.debug('Secret token found in config: {}'.format(val),level=2)
            if not has_secrets:
                raise ValueError(
                    'Secret token found, but no secret file specified')
            if secrets_file.has_option('secrets', val[1:]):
                vn = secrets_file.get('secrets', val[1:])
                #g.logger.debug ('Replacing {} with {}'.format(val,vn))
                val = vn
            else:
                raise ValueError(
                    'secret token {} not found in secrets file {}'.format(
                        val, secrets_filename))

        g.config[k] = _correct_type(val, v['type'])
        if k.find('password') == -1:
            dval = g.config[k]
        else:
            dval = '***********'
        #g.logger.debug ('Config: setting {} to {}'.format(k,dval))

    # main
    try:
        config_file = ConfigParser(interpolation=None)
        config_file.read(args.get('config'))

        if config_file.has_option('general', 'secrets'):
            secrets_filename = config_file.get('general', 'secrets')
            g.logger.debug('secret filename: {}'.format(secrets_filename))
            has_secrets = True
            secrets_file = ConfigParser(interpolation=None)
            try:
                with open(secrets_filename) as f:
                    secrets_file.read_file(f)
            except:
                raise
        else:
            g.logger.debug('No secrets file configured')
        # now read config values

        for k, v in g.config_vals.items():
            #g.logger.debug ('processing {} {}'.format(k,v))
            if k == 'secrets':
                continue

            _set_config_val(k, v)
            #g.logger.debug ("done")

        if g.config['allow_self_signed'] == 'yes':
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            g.logger.debug('allowing self-signed certs to work...')
        else:
            g.logger.debug('strict SSL cert checking is on...')

        g.polygons = []

        # Check if we have a custom overrides for this monitor

        if 'monitorid' in args and args.get('monitorid'):
            sec = 'monitor-{}'.format(args.get('monitorid'))
            if sec in config_file:
                # we have a specific section for this monitor
                for item in config_file[sec].items():
                    k = item[0]
                    v = item[1]
                    if k in g.config_vals:
                        # This means its a legit config key that needs to be overriden
                        g.logger.debug(
                            '[{}] overrides key:{} with value:{}'.format(
                                sec, k, v),level=2)
                        g.config[k] = _correct_type(v,
                                                    g.config_vals[k]['type'])
                    else:
                        # This means its a polygon for the monitor
                        if not g.config['only_triggered_zm_zones'] == 'yes':
                            g.polygons.append({'name': k, 'value': str2tuple(v)})
                            g.logger.debug('adding polygon: {} [{}]'.format(k, v),level=2)
                        else:
                            g.logger.debug ('ignoring polygon: {} as only_triggered_zm_zones is true'.format(k), level=2)
            # now import zones if needed
            # this should be done irrespective of a monitor section
            if g.config['only_triggered_zm_zones'] == 'yes':
                g.config['import_zm_zones'] = 'yes'
            if g.config['import_zm_zones'] == 'yes':
                import_zm_zones(args.get('monitorid'), args.get('reason'))

        else:
            g.logger.info(
                'Ignoring monitor specific settings, as you did not provide a monitor id'
            )
    except Exception as e:
        g.logger.error('Error parsing config:{}'.format(args.get('config')))
        g.logger.error('Error was:{}'.format(e))
        g.logger.fatal('error: Traceback:{}'.format(traceback.format_exc()))
        exit(0)

    # Now lets make sure we take care of parameter substitutions {{}}

    p = r'{{(\w+?)}}'
    for gk, gv in g.config.items():
        if not isinstance(gv, str):
            continue

        sub_vars = re.findall(p, gv)
        for sub_var in sub_vars:
            if g.config[sub_var]:

                g.config[gk] = g.config[gk].replace('{{' + sub_var + '}}',
                                                    g.config[sub_var])
                g.logger.debug('key [{}] is \'{}\' after substitution'.format(
                    gk, g.config[gk]),level=2)

    # Now munge config if testing args provide
    if args.get('file'):
        g.config['wait'] = 0
        g.config['write_image_to_zm'] = 'no'
        g.polygons = []
       
        
    if  args.get('output_path'):
        g.logger.debug ('Output path modified to {}'.format(args.get('output_path')))
        g.config['image_path'] = args.get('output_path')
        g.config['write_debug_image'] = 'yes'
    
   
