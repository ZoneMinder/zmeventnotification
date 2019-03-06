#!/usr/bin/python

import io
import os
import re
import codecs

from setuptools import setup

#Package meta-data.
NAME = 'zmes_hooks'
DESCRIPTION = 'ZoneMinder EventServer hooks'
URL = 'https://github.com/pliablepixels/zmeventserver/tree/master/hook'
AUTHOR_EMAIL = 'pliablepixels@gmail.com'
AUTHOR = 'Pliable Pixels'
LICENSE = 'GPL'


here = os.path.abspath(os.path.dirname(__file__))
def read(*parts):
    with codecs.open(os.path.join(here, *parts), 'r') as fp:
        return fp.read()

def find_version(*file_paths):
    version_file = read(*file_paths)
    version_match = re.search(r"^__version__ = ['\"]([^'\"]*)['\"]", version_file, re.M)
    if version_match:
        return version_match.group(1)
    raise RuntimeError("Unable to find version string.")

setup(name = NAME,
      version = find_version('zmes_hook_helpers','__init__.py'),
      description = DESCRIPTION,
      author = AUTHOR,
      author_email = AUTHOR_EMAIL,
      url = URL,
      license = LICENSE,
      py_modules = ['zmes_hook_helpers.common_params',
                    'zmes_hook_helpers.log',
                    'zmes_hook_helpers.yolo',
                    'zmes_hook_helpers.hog',
                    'zmes_hook_helpers.face',
                    'zmes_hook_helpers.image_manip',
                    'zmes_hook_helpers.utils']
      )

