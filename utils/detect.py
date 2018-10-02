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
 
# construct the argument parse and parse the arguments
ap = argparse.ArgumentParser()
ap.add_argument("-i", "--images", required=True, help="path to images directory")
ap.add_argument("-w", "--win-stride", type=str, default="(4, 4)",
	help="window stride")
ap.add_argument("-p", "--padding", type=str, default="(8, 8)",
	help="object padding")
ap.add_argument("-s", "--scale", type=float, default=1.05,
	help="image pyramid scale")
ap.add_argument("-m", "--mean-shift", type=int, default=-1,
	help="whether or not mean shift grouping should be used")

args = vars(ap.parse_args())
 
 # evaluate the command line arguments (using the eval function like
# this is not good form, but let's tolerate it for the example)
winStride = eval(args["win_stride"])
padding = eval(args["padding"])
meanShift = True if args["mean_shift"] > 0 else False

# initialize the HOG descriptor/person detector
hog = cv2.HOGDescriptor()
hog.setSVMDetector(cv2.HOGDescriptor_getDefaultPeopleDetector())
image = cv2.imread(args["images"])
image = imutils.resize(image, width=min(400, image.shape[1]))
# detect people in the image
start = datetime.datetime.now()
r,w = hog.detectMultiScale(image, winStride=winStride,
	padding=padding, scale=args["scale"], useMeanshiftGrouping=meanShift)

if len(r) > 0:
    print ("person detected")
#result = hog.detectMultiScale(image)
#print (len(r) > 0 ? "Person detected": "")

#print("[INFO] detection took: {}s".format(
#	(datetime.datetime.now() - start).total_seconds()))

