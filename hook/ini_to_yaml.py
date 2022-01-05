import os
from configparser import ConfigParser
from yaml import safe_dump, safe_load
from argparse import ArgumentParser
from pathlib import Path


def ini_to_dict(ini_file):
    config = ConfigParser()
    if Path(ini_file).is_file():
        config.read(ini_file)
    else:
        print('File not found: {}'.format(ini_file))
        exit(1)
    print('INI dumped into dictionary')
    return config._sections


def dict_to_yaml(yaml_file, dict_in):
    try:
        Path(yaml_file).touch(mode=0o666, exist_ok=True)
        # chmod if the file already exists
        os.chmod(yaml_file, 0o666)
    except PermissionError:
        print('Permission denied to write to {}'.format(yaml_file))
        exit(1)
    else:
        with open(yaml_file, 'w') as f:
            safe_dump(config_data, f, default_flow_style=False)


if __name__ == '__main__':
    parser = ArgumentParser(description='Convert INI file to YAML - Experimental')
    parser.add_argument('-i', '--ini', dest='ini_file', required=True, help='INI file to convert')
    parser.add_argument(
        '-o',
        '--output',
        dest='output_file',
        help='Default is to create a .yaml file with the same name in situ; wherever the ini file is. '
             'Use this to change filename and/or path.'
    )
    parser.add_argument('-y', '--yaml', dest='yaml_file', default=None, help='YAML file')
    options = vars(parser.parse_args())
    ini_file = options['ini_file']
    yaml_file = options['yaml_file']
    output_path = options['output_file']

    if yaml_file is None:
        yaml_file = Path(ini_file).with_suffix('.yml')
    config_data = ini_to_dict(ini_file=ini_file)
    # Apply logic to figure out which file it may be
    if config_data.get('hook', {}).get('max_parallel_hooks'):
        print(f"This is assumed to be the ZMES Perl daemon configuration file (Default: ZMEventnotification.ini) "
              f"writing output to {yaml_file}"
              )
        dict_to_yaml(yaml_file=yaml_file, dict_in=config_data)

    elif config_data.get('ml, {}').get('use_sequence'):
        print(f"This is assumed to be the object detection 'hook' configuration file (Default: objectconfig.ini)")
        raise NotImplementedError
        # print(
        #     "This file needs to be processed after conversion to YAML. "
        #     "It does not use the section-> key: value syntax."
        # )
    elif config_data.get('secret'):
        print(f"This is assumed to be the secrets file for the Perl daemon (Default: secrets.ini)")
        dict_to_yaml(yaml_file=yaml_file, dict_in=config_data)
