#!/usr/bin/env python3
"""Migrate objectconfig.ini to objectconfig.yml (YAML format).

Usage:
    python3 tools/config_migrate_yaml.py -c /etc/zm/objectconfig.ini -o /etc/zm/objectconfig.yml
"""

import argparse
import ast
import re
import sys
from configparser import ConfigParser

try:
    import yaml
except ImportError:
    print("PyYAML is required: pip3 install pyyaml", file=sys.stderr)
    sys.exit(1)


# Keys that belong to known sections (flat config keys)
KNOWN_SECTIONS = ['general', 'animation', 'remote', 'object', 'face', 'alpr', 'ml']

# Legacy keys to strip from output
LEGACY_KEYS = {'use_sequence', 'detection_sequence', 'detection_mode'}

# Keys that are Python dict/list literals and need ast.literal_eval
LITERAL_KEYS = {'ml_sequence', 'stream_sequence', 'pyzm_overrides'}


def parse_ini(config_path):
    """Read INI file and return ConfigParser object."""
    cp = ConfigParser(interpolation=None, inline_comment_prefixes='#')
    cp.read(config_path)
    return cp


def safe_eval(value):
    """Try to evaluate a Python literal string; return as-is on failure.

    Handles {{template_var}} by temporarily replacing them with placeholder
    strings so ast.literal_eval can parse the structure.
    """
    if not value or not value.strip():
        return None
    text = value.strip()

    # Replace {{template_var}} with placeholder strings for parsing,
    # then restore them in the resulting structure.
    # Handle both quoted ('{{var}}') and unquoted ({{var}}) cases.
    placeholders = {}
    counter = [0]

    def _replace_quoted(m):
        quote = m.group(1)
        template_token = m.group(2)
        key = '__TMPL_{}__'.format(counter[0])
        counter[0] += 1
        placeholders[key] = template_token
        return "{0}{1}{0}".format(quote, key)

    def _replace_bare(m):
        token = m.group(0)
        key = '__TMPL_{}__'.format(counter[0])
        counter[0] += 1
        placeholders[key] = token
        return "'{}'".format(key)

    # First handle quoted templates: '{{var}}' or "{{var}}"
    substituted = re.sub(r"""(['"])(\{\{\w+?\}\})\1""", _replace_quoted, text)
    # Then handle remaining bare (unquoted) templates: {{var}}
    substituted = re.sub(r'\{\{\w+?\}\}', _replace_bare, substituted)

    try:
        result = ast.literal_eval(substituted)
    except (ValueError, SyntaxError):
        return value

    # Restore {{template_var}} tokens in the parsed structure
    def _restore(obj):
        if isinstance(obj, str):
            return placeholders.get(obj, obj)
        elif isinstance(obj, dict):
            return {_restore(k): _restore(v) for k, v in obj.items()}
        elif isinstance(obj, list):
            return [_restore(item) for item in obj]
        elif isinstance(obj, tuple):
            return tuple(_restore(item) for item in obj)
        return obj

    return _restore(result) if placeholders else result


def is_polygon(value):
    """Check if a value looks like polygon coordinates (e.g. '306,356 1003,341 ...')."""
    parts = value.strip().split(' ')
    if len(parts) < 3:
        return False
    for part in parts:
        coords = part.split(',')
        if len(coords) != 2:
            return False
        try:
            int(coords[0])
            int(coords[1])
        except ValueError:
            return False
    return True


def migrate_section(cp, section_name):
    """Extract key-value pairs from an INI section, skipping legacy keys."""
    result = {}
    if not cp.has_section(section_name):
        return result
    for key, value in cp.items(section_name):
        if key in LEGACY_KEYS:
            continue
        if key in LITERAL_KEYS:
            result[key] = safe_eval(value)
        else:
            result[key] = value
    return result


def migrate_monitor(cp, section_name):
    """Parse a monitor-<id> section into the new YAML structure.

    Separates polygon coords, zone detection patterns, and config overrides.
    """
    overrides = {}
    zones = {}
    zone_patterns = {}

    for key, value in cp.items(section_name):
        if key in LEGACY_KEYS:
            continue

        if key.endswith('_zone_detection_pattern'):
            zone_name = key.rsplit('_zone_detection_pattern', 1)[0]
            zone_patterns[zone_name] = value
        elif is_polygon(value):
            zones[key] = {'coords': value}
        elif key in LITERAL_KEYS:
            overrides[key] = safe_eval(value)
        else:
            overrides[key] = value

    # Attach detection patterns to their zones
    for zone_name, pattern in zone_patterns.items():
        if zone_name in zones:
            zones[zone_name]['detection_pattern'] = pattern
        else:
            # Pattern for a zone not defined here (maybe a ZM zone)
            zones[zone_name] = {'detection_pattern': pattern}

    if zones:
        overrides['zones'] = zones

    return overrides


def build_yaml(cp):
    """Build the full YAML dict from a parsed INI ConfigParser."""
    output = {}

    for section in KNOWN_SECTIONS:
        data = migrate_section(cp, section)
        if data:
            output[section] = data

    # Handle monitor sections
    monitors = {}
    for section in cp.sections():
        if section.startswith('monitor-'):
            mid = section.split('monitor-', 1)[1]
            try:
                mid = int(mid)
            except ValueError:
                pass
            monitors[mid] = migrate_monitor(cp, section)

    if monitors:
        output['monitors'] = monitors

    return output


def represent_str(dumper, data):
    """Custom representer: use block style for multiline, plain for simple strings."""
    if '\n' in data:
        return dumper.represent_scalar('tag:yaml.org,2002:str', data, style='|')
    return dumper.represent_scalar('tag:yaml.org,2002:str', data)


def main():
    parser = argparse.ArgumentParser(description='Migrate objectconfig.ini to YAML format')
    parser.add_argument('-c', '--config', required=True, help='Path to input objectconfig.ini')
    parser.add_argument('-o', '--output', default='objectconfig.yml', help='Path to output YAML file (default: objectconfig.yml)')
    args = parser.parse_args()

    cp = parse_ini(args.config)
    yaml_data = build_yaml(cp)

    yaml.add_representer(str, represent_str)

    with open(args.output, 'w') as f:
        f.write("# Migrated from {}\n".format(args.config))
        f.write("# Please review and adjust as needed\n\n")
        yaml.dump(yaml_data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

    print("Migration complete: {} -> {}".format(args.config, args.output))


if __name__ == '__main__':
    main()
