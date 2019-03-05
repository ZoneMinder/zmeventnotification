#!/usr/bin/python

import io
import os
import sys

from setuptools import setup


# Package meta-data.
NAME = 'zmes_hooks'
DESCRIPTION = 'ZoneMinder EventServer hooks'
URL = 'https://github.com/pliablepixels/zmeventserver/tree/master/hook'
EMAIL = 'pliablepixels@gmail.com'
AUTHOR = 'Pliable Pixels'
VERSION = '3.0'

setup(name=NAME,
      version=VERSION,
      py_modules=['zmes_hook_helpers.common_params',
                  'zmes_hook_helpers.log',
                  'zmes_hook_helpers.yolo',
                  'zmes_hook_helpers.hog',
                  'zmes_hook_helpers.face',
                  'zmes_hook_helpers.image_manip',
                  'zmes_hook_helpers.utils']
      )
