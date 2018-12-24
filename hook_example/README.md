### Note

**I don't plan to provide support for these hooks. They are for reference only and require setup and some degree of know how**


### Limitations

* Only tested with ZM 1.32. May or may not work with older versions

### What
This is just an example of how you can use the new `hook` feature of the notification server
to invoke a custom script on the event before it generates an alarm. This implements a hook script that detects
for persons in an image that raised an alarm before sending out a notification. 

There are two sample detection scripts. You can switch between them by changing the value of
`DETECTION_SCRIPT` in `detect_wrapper.sh`

**Both of these scripts require setup, please run from command line first and 
make sure deps are installed**

Please don't ask me questions on how to use them. Please read the comments and figure it out.

Try to keep the images less than 800px on the largest side. The larger the image, the longer
it will take to detect

### Dependencies and Installation

*  Make sure you have Python3. Python2 is not supported
*  You need to have `pip` installed. On ubuntu, it is `sudo apt install python-pip`
*  Clone the event server and go to the `hook_example` directory. If you haven't already cloned it is:

```bash
git clone https://github.com/pliablepixels/zmeventserver 
cd zmeventserver/hook_example
```

* Install the object detection dependencies:
```bash
sudo pip install -r  requirements.txt 
```

* Copy the models and weights:
```bash
sudo mkdir -p /var/detect/images
sudo mkdir -p /var/detect/models
sudo mkdir -p /var/detect/models/yolov3 # if you are using YoloV3
sudo mkdir -p /var/detect/models/tinyyolo # if you are using TinyYoloV3

# if you want to use YoloV3 (slower, accurate)
sudo wget https://raw.githubusercontent.com/pjreddie/darknet/master/cfg/yolov3.cfg -O /var/detect/models/yolov3/yolov3.cfg
sudo wget https://raw.githubusercontent.com/pjreddie/darknet/master/data/coco.names -O /var/detect/models/yolov3/yolov3_classes.txt
sudo wget https://pjreddie.com/media/files/yolov3.weights -O /var/detect/models/yolov3/yolov3.weights

# if you want to use TinyYoloV3 (faster, less accurate)
sudo wget https://pjreddie.com/media/files/yolov3-tiny.weights -O /var/detect/models/tinyyolo/yolov3-tiny.weights
sudo wget https://raw.githubusercontent.com/pjreddie/darknet/master/cfg/yolov3-tiny.cfg -O /var/detect/models/tinyyolo/yolov3-tiny.cfg
sudo wget https://raw.githubusercontent.com/pjreddie/darknet/master/data/coco.names -O /var/detect/models/tinyyolo/yolov3-tiny.txt
```

* Now make sure it all RW accessible by `www-data` (or `apache`)
```
sudo chown -R www-data:www-data /var/detect/ #(change www-data to apache for CentOS/Fedora)
```

* Edit `detect_wrapper.sh` and change:
    * `PORTAL` to your portal url (example: https://myip/server/zm)
    * `USERNAME` and `PASSWORD` to your ZM username and password
    * Study the rest of the file to see if you need to change anything else     


* Now copy your detection files to `/usr/bin` -> `sudo cp detect_* /usr/bin`

* Test operation:
```
sudo -u www-data /usr/bin/detect_wrapper.sh <eid> # replace www-data with apache if needed

```

This will try and download the configured frame for alarm <eid> and analyze it. Replace with your own EID (Example 123456)
The files will be in `/var/detect/images`
For example: 
if you configured `FID` to be `bestmatch` you'll see two files `<eid>-alarm.jpg` and `<eid>-snapshot.jpg`
If you configured `FID` to be `snapshot` or a specific number, you'll see one file `<eid>.jpg`

The above command will also try and run detection.

If it doesn't work, go back and figure out where you have a problem

### Types of detection

### detect_hog.py: using OpenCV SVM HOG (very fast, not accurate)

You can manually invoke it to test:

```bash
./detect_hog.py --image image.jpg
```

The detection uses a very fast, but not very accurate OpenCV model (hog.detectMultiScale). 
The good part is that it is extremely fast can can be used for realtime needs. 
Fiddle with the settings in detect.py (stride/scale) to get more accuracy at the cost of speed.

### detect_yolo.py:  using OpenCV DNN with Tiny YoloV3 (almost comparable with HOG in speed, more accurate)

The detection uses OpenCV's DNN module and Tiny YoloV3 to predict multiple labels with score.

You can manually invoke it to test:

```bash
./detect_yolo.py --image image.jpg --config path/to/config/file --weight path/to/weights/file --label path/to/label/file --pattern "<somepattern>"
```

Where `<somepattern>` is the python regexp to filter. Example `"(person | car)"`  or `".*"` for all labels


If you are using YOLO models, you will need the following data files (if you followed the installation directions, you already have them):
* weights: https://pjreddie.com/media/files/yolov3-tiny.weights
* config:  https://raw.githubusercontent.com/pjreddie/darknet/master/cfg/yolov3-tiny.cfg
* labels:  https://raw.githubusercontent.com/pjreddie/darknet/master/data/coco.names




### detect_yolo.py:  using OpenCV DNN with YoloV3 (much slower, accurate)

The detection uses OpenCV's DNN module and YoloV3 to predict multiple labels with score.

You can manually invoke it to test:

```bash
./detect_yolo.py --image image.jpg --config path/to/config/file --weight path/to/weights/file --label path/to/label/file --pattern "<somepattern>"
```

Where `<somepattern>` is the python regexp to filter. Example `"(person | car)"`  or `".*"` for all labels

If you are using YOLO models, you will need the following data files (if you followed the installation directions, you already have them):
* weights: https://pjreddie.com/media/files/yolov3.weights
* config: https://raw.githubusercontent.com/pjreddie/darknet/master/cfg/yolov3.cfg
* labels: https://raw.githubusercontent.com/pjreddie/darknet/master/data/coco.names

(Note: `coco.names` is the label file the script needs. It is common for both tiny or regular yolo)


### Performance comparison

DNNs perform very well on a GPU. My ZM server doesn't have a GPU. 
On a Intel Xeon 3.16GHz 4Core machine:
- HOG takes 0.24s
- YOLOv3 with tiny-yolo takes 0.32s
- YOLOv3 takes 2.4s


As always, if you are trying to figure out how this works, do this in 3 steps:

**STEP 1: Make sure the scripts(s) work**
- Run the python script manually with `--image <path/to/image/image.jpg>` to see if it works
- `./detect_wrapper.sh <eid>` --> make sure it downloads a proper image for that eid. Make sure it correctly invokes detect.py If not, fix it. Note that by default the wrapper script passed the `--delete` option to remove the downloaded image. While testing, remove the `--delete` option
- Make sure the `IMAGE_PATH` you've chosen in `detect_wrapper.sh` is WRITABLE by www-data (or apache) before you move to step 2

**STEP 2: run zmeventnotification in MANUAL mode**
* `sudo zmdc.pl stop zmeventnotification.pl`
*  change verbose to 1 in `zmeventnotification.ini`
*  `sudo -u www-data ./zmeventnotification.pl  --config ./zmeventnotification.ini`
*  Force an alarm, look at logs

**STEP 3: integrate with the actual daemon**

* You should know how to do this already
