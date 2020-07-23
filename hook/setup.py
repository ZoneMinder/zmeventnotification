#!/usr/bin/python3

import io
import os
import re
import codecs

from setuptools import setup

#Package meta-data
NAME = 'zmes_hooks'
DESCRIPTION = 'ZoneMinder EventServer hooks'
URL = 'https://github.com/pliablepixels/zmeventserver/'
AUTHOR_EMAIL = 'pliablepixels@gmail.com'
AUTHOR = 'Pliable Pixels'
LICENSE = 'GPL'
INSTALL_REQUIRES = [
    'numpy', 'requests', 'Shapely', 'imutils', 'pyzm>=0.1.16', 'scikit-learn', 'future', 'imageio','imageio-ffmpeg','pygifsicle'
]

here = os.path.abspath(os.path.dirname(__file__))
# read the contents of your README file
with open(os.path.join(here, 'README.md'), encoding='utf-8') as f:
    long_description = f.read()


def read(*parts):
    with codecs.open(os.path.join(here, *parts), 'r') as fp:
        return fp.read()


def find_version(*file_paths):
    version_file = read(*file_paths)
    version_match = re.search(r"^__version__ = ['\"]([^'\"]*)['\"]",
                              version_file, re.M)
    if version_match:
        return version_match.group(1)
    raise RuntimeError("Unable to find version string.")


setup(name=NAME,
      version=find_version('zm_ml', '__init__.py'),
      description=DESCRIPTION,
      author=AUTHOR,
      author_email=AUTHOR_EMAIL,
      long_description=long_description,
      long_description_content_type='text/markdown',
      url=URL,
      license=LICENSE,
      install_requires=INSTALL_REQUIRES,
      py_modules=[
          'zm_ml.common_params', 'zm_ml.log',
          'zm_ml.yolo', 'zm_ml.hog',
          'zm_ml.face', 'zm_ml.face_train',
          'zm_ml.alpr', 'zm_ml.image_manip',
          'zm_ml.apigw', 'zm_ml.utils'
      ])
