#!/usr/bin/python3

# argparse k,v handling: https://stackoverflow.com/a/52014520/1361529
import sys
from configupdater import ConfigUpdater
import argparse
import logging

def parse_var(s):
    items = s.split('=',1)
    sk = items[0].split(':',1)
    if len(sk) == 1:
        key = sk[0]
        section = '_global_'
    else:
        key=sk[1]
        section=sk[0]

    key = key.strip() # we remove blanks around keys, as is logical
    section = section.strip() # we remove blanks around keys, as is logical

    if len(items) > 1:
        # rejoin the rest:
        value = '='.join(items[1:])
    return (section, key, value)


def parse_vars(items):
    d = {}
    if items:
        for item in items:
            section, key, value = parse_var(item)
            #logger.debug ('Updating section:{} key:{} to value:{}'.format(section,key,value))
            if not d.get(section):
                d[section]={}
            d[section][key] = value
    return d


# main
logger = logging.getLogger()
handler = logging.StreamHandler()
formatter = logging.Formatter('[%(asctime)s] [%(filename)s:%(lineno)d] %(levelname)s - %(message)s','%m-%d %H:%M:%S')

handler.setFormatter(formatter)
logger.addHandler(handler)


ap = argparse.ArgumentParser(
    description='config editing script',
    epilog='''
            Example:
            %(prog)s --input /etc/zm/zmeventnotification.ini --output mynewconf.ini --set network:address=comment_out general:restart_interval=60 network:port=9999 general:base_data_path='/my new/path with/spaces'

        '''
    )
ap.add_argument('-c', '--config', '-i', '--input', help='input ini file with path', required=True)
ap.add_argument('-o', '--output', help='output file with path')
ap.add_argument('--nologs', action='store_true', help='disable logs')
ap.add_argument('--set',
                        metavar='[SECTION:]KEY=VALUE',
                        nargs='+',
                        help='''
                                Set a number of key-value pairs.
                                (do not put spaces before or after the = sign). 
                                If a value contains spaces, you should define 
                                it within quotes. If you omit the SECTION:, all keys in all
                                sections that match your key will be updated. 
                                If you do specify a section, remember to add the : after it
                                Finally, use the special keyword of 'comment_out' if you want 
                                to comment out a key. There is no way to 'uncomment' as once it is 
                                a comment, it won't be found as a key.
                            ''')

args, u = ap.parse_known_args()
args = vars(args)

if args.get('nologs'):
    logger.setLevel(logging.CRITICAL + 1)
else:
    logger.setLevel(logging.DEBUG) 

values = parse_vars(args['set'])


input_file = args['config']
updater = ConfigUpdater(space_around_delimiters=False)
logger.debug('reading input: {}'.format(input_file))
updater.read(input_file)


for sec in values:
    if sec == '_global_': 
        continue
    for key in values[sec]:
        if values[sec][key]=='comment_out' and updater[sec].get(key):
            logger.debug ('commenting out [{}]->{}={}'.format(sec,key,updater[sec][key].value))            
            updater[sec][key].key = '#{}'.format(key)
             
        else:
            logger.debug ('setting [{}]->{}={}'.format(sec,key,values[sec][key]))            
            updater[sec][key] = values[sec][key]

if values.get('_global_'):
    for key in values.get('_global_'):
        for secname in updater.sections():
            if updater.has_option(secname,key):
                if values['_global_'][key]=='comment_out' and updater[secname].get(key):
                    logger.debug ('commenting out [{}]->{}={}'.format(secname,key,updater[secname][key].value))            
                    updater[secname][key].key = '#{}'.format(key)
                else:
                    updater[secname][key] = values['_global_'][key]
                    logger.debug ('{} found in [{}] setting to {}'.format(key,secname,values['_global_'][key]))

       
if args.get('output'):
    logger.debug ('writing output: {}'.format(args.get('output')))
    output_file_handle =  open(args['output'],'w') 
else:
    logger.debug ('writing output: stdout') 
    output_file_handle = sys.stdout

updater.write(output_file_handle)
if output_file_handle is not sys.stdout:
    output_file_handle.close()

