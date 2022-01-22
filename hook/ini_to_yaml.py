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
        _mode = 0o666
        Path(yaml_file).touch(mode=_mode, exist_ok=True)
        # chmod if the file already exists
        os.chmod(yaml_file, _mode)
    except PermissionError:
        print(f'Exception while trying to create empty file using mode={_mode}. '
              f'Permission denied to write to >>> {yaml_file}')
        exit(1)
    else:
        try:
            with open(yaml_file, 'w') as f:
                safe_dump(config_data, f, default_flow_style=False)
        except Exception as e:
            print(f"Exception while trying to write data into >>> {yaml_file}")
            print(f"EXCEPTION MESSAGE >>> {e}")
            raise e
        else:
            print(f"Converted INI dictionary into YAML syntax on disk!")


if __name__ == '__main__':
    parser = ArgumentParser(description='Convert INI file to YAML - Experimental')
    parser.add_argument(
        '-i',
        '--ini',
        dest='ini_file',
        required=True,
        help='Input INI file to convert to YAML syntax - REQUIRED'
    )
    parser.add_argument(
        '-o',
        '--output',
        dest='output_file',
        default=False,
        help='Use this to change filename and/or path. Default logic is to create a .yml file with the same '
             'name in-situ; wherever the current .ini file is.'
    )
    options = vars(parser.parse_args())
    # This is a required key so no need to use .get()
    ini_file = options['ini_file']
    # output_file has a default of False, no need to use .get()
    output_path = options['output_file']
    if output_path is not False:
        yaml_file = Path(output_path)
    else:
        # This takes the current INI file name and replaces the suffix with '.yml'
        yaml_file = Path(ini_file).with_suffix('.yml')
    # Get the ini file into a dictionary
    config_data = ini_to_dict(ini_file=ini_file)
    # Apply logic to figure out which file it may be
    _parse = False
    if config_data.get('hook', {}).get('max_parallel_hooks'):
        print(f"This is assumed to be the ZMES Perl daemon configuration file (Default: ZMEventnotification.ini) "
              f"writing output to {yaml_file}"
              )
        _parse = True
    elif config_data.get('secret') or config_data.get('secrets'):
        print(f"This is assumed to be the secrets file for the Perl daemon (Default: secrets.ini)")
        _parse = True
    elif config_data.get('ml', {}).get('stream_sequence') or config_data.get('ZMES'):
        print(f"This is assumed to be the object detection 'hook' configuration file (Default: objectconfig.ini)")
        print(f"\nYou must convert objectconfig manually, use the provided example config to copy "
              f"your configuration over.")
        raise NotImplementedError
    elif config_data.get('MLAPI_SECRET_KEY') or config_data.get('MLAPI') or config_data.get('zmes_keys'):
        print(f"This is assumed to be a configuration or secrets file associated with MLAPI")
        print(f"\nYou must convert this file manually, use the provided example config to copy "
              f"your configuration over.")
        raise NotImplementedError

    if _parse:
        dict_to_yaml(yaml_file=yaml_file, dict_in=config_data)
