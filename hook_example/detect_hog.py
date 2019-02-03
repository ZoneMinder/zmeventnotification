#!/usr/bin/python

# version: 2.1

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
import configparser

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
ap.add_argument("--mask",  help="config file with mask definitions")
ap.add_argument("--monitor",  help="monitor id - needed for mask")


args,u = ap.parse_known_args()
args = vars(args)

def str2arr(str):
    return  [map(int,x.strip().split(',')) for x in str.split(' ')]

# main handler

# process crop masks, if they exist
masks = np.array([[]])
config = configparser.ConfigParser()
if config.read(args["mask"]):
   if args["monitor"]: # check if a mask for that monitor is specified
        try:
            itms = config.items(args["monitor"])
            if itms: logger.info ("mask definition found for monitor:"+args["monitor"])
            a=[]
            for k,v in itms:
                a.append(str2arr(v))
                masks = np.asarray(a)
        except configparser.NoSectionError:
                logger.info ("no mask found for monitor:"+args["monitor"])
   else:
        logger.error ("Ignoring masks, as you did not provide a monitor id")
 
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

if masks.size:
    logger.info ("creating masked image...")
    filter_mask = np.zeros(image.shape, dtype=np.uint8)
    cv2.fillPoly(filter_mask, pts=masks, color=(255,255,255))
    masked_image = cv2.bitwise_and(image, filter_mask)
    image = masked_image
    logger.info ("overwriting masked image: "+filename1)
    cv2.imwrite (filename1,image)


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
     if masks.size:
            logger.info ("creating masked image...")
            filter_mask = np.zeros(image.shape, dtype=np.uint8)
            cv2.fillPoly(filter_mask, pts=masks, color=(255,255,255))
            masked_image = cv2.bitwise_and(image, filter_mask)
            image = masked_image
            logger.info ("overwriting masked image: "+filename1)
            cv2.imwrite (filename2,image)

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

