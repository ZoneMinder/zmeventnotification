#!/usr/bin/python

# version: 2.0

# Please don't ask me questions about this script
# its a simple OpenCV person detection script I've proved as a sample "hook" you can add to the notification server

# credit: https://www.pyimagesearch.com/2015/11/16/hog-detectmultiscale-parameters-explained/

# import the necessary packages
from __future__ import print_function
from imutils.object_detection import non_max_suppression
from imutils import paths
import numpy as np
import argparse
import imutils
import cv2
import datetime
import os
import re
import sys

# set up logging to syslog
import logging
import logging.handlers
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)
handler = logging.handlers.SysLogHandler('/dev/log')
formatter = logging.Formatter('detect_hog:[%(process)d]: %(levelname)s [%(message)s]')
handler.formatter = formatter
logger.addHandler(handler)
 
# construct the argument parse and parse the arguments
ap = argparse.ArgumentParser()
ap.add_argument("-d", "--delete", action="store_true",  help="delete image after processing")
ap.add_argument("-t", "--time", action="store_true",  help="print time to detect")
ap.add_argument("-i", "--image", required=True, help="image with path")
ap.add_argument("-w", "--win-stride", type=str, default="(4, 4)", help="window stride")
ap.add_argument( "--padding", type=str, default="(8, 8)", help="object padding")
ap.add_argument("-s", "--scale", type=float, default=1.05, help="image pyramid scale")
ap.add_argument("-m", "--mean-shift", type=int, default=-1, help="whether or not mean shift grouping should be used")
ap.add_argument("-b", "--bestmatch", action="store_true", help="evaluates both alarm and snapshot")


args,u = ap.parse_known_args()
args = vars(args)
 
 # evaluate the command line arguments (using the eval function like
# this is not good form, but let's tolerate it for the example)
winStride = eval(args["win_stride"])
padding = eval(args["padding"])
meanShift = True if args["mean_shift"] > 0 else False

# initialize the HOG descriptor/person detector
hog = cv2.HOGDescriptor()
hog.setSVMDetector(cv2.HOGDescriptor_getDefaultPeopleDetector())

filename1 = args["image"]
filename2 = ""

if args["bestmatch"]:
    name, ext = os.path.splitext(filename1)
    filename1 = name + '-alarm'+ext
    filename2 = name + '-snapshot'+ext

logger.info ("Analyzing: "+filename1)
image = cv2.imread(filename1)
image = imutils.resize(image, width=min(400, image.shape[1]))
# detect people in the image
start = datetime.datetime.now()
r,w = hog.detectMultiScale(image, winStride=winStride,
	padding=padding, scale=args["scale"], useMeanshiftGrouping=meanShift)

if len(r) > 0:
    print ("detected: person")
elif filename2:
     logger.debug ("person detect failed for "+filename1+" trying "+filename2)
     image = cv2.imread(filename2)
     image = imutils.resize(image, width=min(400, image.shape[1]))
     # detect people in the image
     r,w = hog.detectMultiScale(image, winStride=winStride,
	 padding=padding, scale=args["scale"], useMeanshiftGrouping=meanShift)
     if len(r) > 0:
        print ("detected: person")

    

if (args["time"]):
    logger.debug("detection took: {}s".format((datetime.datetime.now() - start).total_seconds()))

if (args["delete"]):
    os.remove(filename1)
    if filename2:
        os.remove(filename2)

