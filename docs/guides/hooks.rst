Machine Learning Hooks
======================

.. note::

        Before you install machine learnings hooks, please make sure you have installed
        the Event Notification Server (:doc:`install`) and have it working properly

.. important::

        Please don't ask me basic questions like "pip3 command not found" or
        "cv2 not found" - what do I do? Hooks require some terminal
        knowledge and familiarity with troubleshooting. I don't plan to
        provide support for these hooks. They are for reference only

Limitations
~~~~~~~~~~~

- Only tested with ZM 1.32+. May or may not work with older versions
- Needs Python3 (Python2 is not supported)

What
~~~~

Kung-fu machine learning goodness.

This is an example of how you can use the ``hook`` feature of the
notification server to invoke a custom script on the event before it
generates an alarm. I currently support object detection and face
recognition.

Please don't ask me questions on how to use them. Please read the
extensive documentation and ini file configs

.. _hooks_install:

Installation
~~~~~~~~~~~~

Option 1: Automatic install
^^^^^^^^^^^^^^^^^^^^^^^^^^^

-  You need to have ``pip3`` installed. On ubuntu, it is
   ``sudo apt install python3-pip``, or see
   `this <https://pip.pypa.io/en/stable/installing/>`__
-  Clone the event server and go to the ``hook`` directory

.. code:: bash

    git clone https://github.com/pliablepixels/zmeventnotification # if you don't already have it downloaded

    cd zmeventnotification

-  (OPTIONAL) Edit ``hook/zm_event_start.sh`` and change:

   -  ``CONFIG_FILE`` to point to the right config file, if you changed
      paths

::

    sudo -H ./install.sh # and follow the prompts


.. _install_specific_models:

Starting version 5.13.3, you can *optionally* choose to only install specific models by passing them as variables to the install script. The variables are labelled as ``INSTALL_<model>`` with possible values of ``yes`` (default) or ``no``. ``<model>`` is the specific model.

So for example:

::

  sudo INSTALL_CSPN=no INSTALL_TINYYOLO=no ./install.sh

Will only install the ``YOLOv3 (full)`` model but will skip the ``CSPN (Cross Stage Partial Networks)`` model and the "Tiny YOLO" models.


.. _opencv_install:

**Note:**: If you plan on using object detection, starting v5.0.0 of the ES, the setup script no longer installs opencv for you. This is because you may want to install your own version with GPU accelaration or other options. There are two options to install OpenCV:

  - You install a pip package. Very easy, but you don't get GPU support
  - You compile from source. Takes longer, but you get all the right modules as well as GPU support. Instructions are simple, if you follow them well.

  .. important::

    However you choose to install openCV, you need a minimum version of `4.1.1`. Using a version below that will very likely not work.


Installing OpenCV: Using the pip package (Easy, but not recommended)
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
::

  # Note this does NOT enable GPU support
  # It also seems to miss modules like bgsem etc

  sudo -H pip3 install opencv-contrib-python

  # NOTE: Do NOT install both opencv-contrib-python and opencv packages via pip. The contrib package includes opencv+extras


Installing OpenCV: from source (Recommended)
'''''''''''''''''''''''''''''''''''''''''''''''
General installation instructions are available at the `official openCV site <https://docs.opencv.org/master/d7/d9f/tutorial_linux_install.html>`__. However, see below, if you are looking for GPU support:

If you want to install a version with GPU support, I'd recommend you install OpenCV 4.2.x because it supports a CUDA backend for deep learning. Adrian's blog has a `good howto <https://www.pyimagesearch.com/2020/02/03/how-to-use-opencvs-dnn-module-with-nvidia-gpus-cuda-and-cudnn/>`__ on compiling OpenCV 4.2.x from scratch.

**I would strongly recommend you build from source, if you are able to. Pre built packages are not official from OpenCV and often seem to break/seg fault on different configurations.**

.. _opencv_seg_fault:

Make sure OpenCV works
+++++++++++++++++++++++

.. important::

  After you install opencv, make sure it works. Start python3 and inside the interpreter, do a ``import cv2``. If it seg faults, you have a problem with the package you installed. Like I said, I've never had issues after building from source.

  Note that if you get an error saying ``cv2 not found`` that means you did not install it in a place python3 can find it (you might have installed it for python2 by mistake)



**Note 3:** if you want to add "face recognition" you also need to do

::

    sudo apt-get install libopenblas-dev liblapack-dev libblas-dev  # not mandatory, but gives a good speed boost!
    sudo -H pip3 install face_recognition # mandatory

Takes a while and installs a gob of stuff, which is why I did not add it
automatically, especially if you don't need face recognition.

Note, if you installed ``face_recognition`` earlier without blas, do this:

.. code:: bash

  sudo -H pip3 uninstall dlib
  sudo -H pip3 uninstall face-recognition
  sudo apt-get install libopenblas-dev liblapack-dev libblas-dev # this is the important part
  sudo -H pip3 install dlib --verbose --no-cache-dir # make sure it finds openblas
  sudo -H pip3 install face_recognition

Option 2: Manual install
^^^^^^^^^^^^^^^^^^^^^^^^
If automatic install fails for you, or you like to be in control, take a look at what ``install.sh`` does. I used to maintain explict instructions on manual install, but its painful to keep this section in sync with ``install.sh``


Post install steps
~~~~~~~~~~~~~~~~~~

-  Make sure you edit your installed ``objectconfig.ini`` to the right
   settings. You MUST change the ``[general]`` section for your own
   portal.
-  Make sure the ``CONFIG_FILE`` variable in ``zm_event_start.sh`` is
   correct


Test operation
~~~~~~~~~~~~~~

::

    sudo -u www-data /var/lib/zmeventnotification/bin/zm_event_start.sh <eid> <mid> # replace www-data with apache if needed

This will try and download the configured frame for alarm and analyze
it. Replace with your own EID (Example 123456) The files will be in
``/var/lib/zmeventnotification/images`` For example: if you configured
``frame_id`` to be ``bestmatch`` you'll see two files
``<eid>-alarm.jpg`` and ``<eid>-snapshot.jpg`` If you configured
``frame_id`` to be ``snapshot`` or a specific number, you'll see one
file ``<eid>.jpg``

The ``<mid>`` is optional and is the monitor ID. If you do specify it,
it will pick up the right mask to apply (if it is in your config)

The above command will also try and run detection.

If it doesn't work, go back and figure out where you have a problem

-  Other configuration notes, after you get everything working

   -  Set ``delete_after_analyze`` to ``yes`` so that downloaded images
      are removed after analysis. In the default installation, the
      images are kept in ``/var/lib/zmeventnotification/images`` so you can debug.
   -  Remember these rules:

      -  ``frame_id=snapshot`` will work for any ZM >= 1.32
      -  If you are running ZM < 1.33, to enable ``bestmatch`` or
         ``alarm`` you need to enable the monitor to store JPEG frames
         in its ZM monitor->storage configuration in ZM
      -  If you are running ZM >= 1.33, you can use all fid modes
         without requiring to enable frames in storage


Upgrading
~~~~~~~~~
To upgrade at a later stage, see :ref:`upgrade_es_hooks`.

Sidebar: Local vs. Remote Machine Learning
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Starting v5.0, you can now choose to run the machine learning code on a separate server. This can free up your local ZM server resources if you have memory/CPU constraints. See :ref:`this FAQ entry <local_remote_ml>`.


.. _supported_models:

Which models should I use?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

-  As of April 2020, I'd recommend you use CSPR for object detection. It is both faster and more accurate than YoloV3. Note however that I've not enabled it by default, because that model requires OpenCV 4.3 or above. If you use it with versions less than 4.3, it will either error out, or not detect anything. **Please Note** that the CSPR weights file needs to be *manually downloaded* and placed in the right place. If you don't have OpenCV >=4.3, use YoloV3. 

- If you are constrained in memory, use tinyyolo

- For face recognition, use ``face_model=cnn`` for more accuracy and ``face_model=hog`` for better speed


Troubleshooting
~~~~~~~~~~~~~~~

-  In general, I expect you to debug properly. Please don't ask me basic
   questions without investigating logs yourself
-  Always run ``zm_event_start.sh`` in manual mode first to make sure it
   works
-  Make sure you've set up debug logging as described in :ref:`es-hooks-logging`
-  One of the big reasons why object detection fails is because the hook
   is not able to download the image to check. This may be because your
   ZM version is old or other errors. Some common issues:

   -  Make sure your ``objectconfig.ini`` section for ``[general]`` are
      correct (portal, user,admin)
   -  For object detection to work, the hooks expect to download images
      of events using
      ``https://yourportal/zm/?view=image&eid=<eid>&fid=snapshot`` and
      possibly ``https://yourportal/zm/?view=image&eid=<eid>&fid=alarm``
   -  Open up a browser, log into ZM. Open a new tab and type in
      ``https://yourportal/zm/?view=image&eid=<eid>&fid=snapshot`` in
      your browser. Replace ``eid`` with an actual event id. Do you see
      an image? If not, you'll have to fix/update ZM. Please don't ask
      me how. Please post in the ZM forums
   -  Open up a browser, log into ZM. Open a new tab and type in
      ``https://yourportal/zm/?view=image&eid=<eid>&fid=alarm`` in your
      browser. Replace ``eid`` with an actual event id. Do you see an
      image? If not, you'll have to fix/update ZM. Please don't ask me
      how. Please post in the ZM forums

Types of detection
~~~~~~~~~~~~~~~~~~

As of today, the following detection types are supported - these are all attributes you can put into the ``model`` attribute. You can put multiple and comma separate them as well.

* ``yolo`` - An object detector. Detects 80 types of objects.

  * Yolo supports two modes, a ``tiny`` mode that takes less resources and is faster. And a regular mode, that is more accurate but resource hungry. These models are controlled by the ``weights`` and ``config`` files you use with yolo. 
* ``hog`` - A very innacurate, but very fast person detector. Use this *only* if you are not able to run yolo, even with the "tiny" weights.
* ``face`` - face detection and recognition
* ``alpr`` - license plate recognition. Needs to be paired with yolo (i.e. ``yolo,alpr``)

You can switch detection type by using
``model=<detection_type1>,<detection_type2>,....`` in your
``objectconfig.ini``

Example:

``model=yolo,hog,face`` will run full Yolo, then HOG, then face
recognition.

Note that you can change ``model`` on a per monitor basis too. Read the
comments in ``objectconfig.ini``

If you select yolo, you can add a ``model_type=tiny`` to use tiny YOLO
instead of full yolo weights. Again, please readd the comments in
``objectconfig.ini``

How to use license plate recognition
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Three ALPR options are provided: 

- `Plate Recognizer <https://platerecognizer.com>`__ . It uses a deep learning model that does a far better job than OpenALPR (based on my tests). The class is abstracted, obviously, so in future I may add local models. For now, you will have to get a license key from them (they have a `free tier <https://platerecognizer.com/pricing/>`__ that allows 2500 lookups per month)
- `OpenALPR <https://www.openalpr.com>`__ . While OpenALPR's detection is not as good as Plate Recognizer, when it does detect, it provides a lot more information (like car make/model/year etc.)
- `OpenALPR command line <http://doc.openalpr.com/compiling.html>`__. This is a basic version of OpenALPR that can be self compiled and executed locally. It is far inferior to the cloud services and does NOT use any form of deep learning. However, it is free, and if you have a camera that has a good view of plates, it will work.

To enable alpr, simple add `alpr` to `models`. You will also have to add your license key to the ``[alpr]`` section of ``objdetect.ini``

This is an example config that uses plate recognizer:

::

  models = yolo,alpr

  [alpr]
  alpr_service=plate_recognizer
  # If you want to host a local SDK https://app.platerecognizer.com/sdk/
  #alpr_url=https://localhost:8080
  # Plate recog replace with your api key
  alpr_key=KEY
  # if yes, then it will log usage statistics of the ALPR service
  platerec_stats=no
  # If you want to specify regions. See http://docs.platerecognizer.com/#regions-supported
  #platerec_regions=['us','cn','kr']
  # minimal confidence for actually detecting a plate
  platerec_min_dscore=0.1
  # minimal confidence for the translated text
  platerec_min_score=0.2


This is an example config that uses OpenALPR:

::

  models = yolo,alpr

  [alpr]
  alpr_service=open_alpr
  alpr_key=SECRET

  # For an explanation of params, see http://doc.openalpr.com/api/?api=cloudapi
  openalpr_recognize_vehicle=1
  openalpr_country=us
  openalpr_state=ca
  # openalpr returns percents, but we convert to between 0 and 1
  openalpr_min_confidence=0.3


This is an example config that uses OpenALPR command line:

::

  models = yolo,alpr

  [alpr]
  alpr_service=open_alpr_cmdline

  openalpr_cmdline_binary=alpr

  # Do an alpr -help to see options, plug them in here
  # like say '-j -p ca -c US' etc.
  # keep the -j because its JSON

  # Note that alpr_pattern is honored
  # For the rest, just stuff them in the cmd line options

  openalpr_cmdline_params=-j -d
  openalpr_cmdline_min_confidence=0.3


**NOTE**: The command line version depends on your ``alpr`` application to be correctly set up. You should make sure that if you do an ``alpr -j someimage.jpg`` (where ``someimage.jpg`` is a picture of a car with a license plate) that this command produces a legitimate JSON output **without** any sort of errors/warnings.  If you see any form of messages before the JSON output, this integration won't work. It seems in certain cases, the openALPR package bundled with OSes have issues, so you should `compile OpenALPR on your own <http://doc.openalpr.com/compiling.html>`__.

How license plate recognition will work
''''''''''''''''''''''''''''''''''''''''

- To save on  API calls, the code will only invoke remote APIs if a vehicle is detected
- This also means you MUST specify yolo along with alpr
- While the newly added openalpr_cmd_line option does not have an API limitation, it will still need yolo in front. I was too lazy to filter it out. Maybe later.


How to use face recognition
^^^^^^^^^^^^^^^^^^^^^^^^^^^

Face Recognition uses
`this <https://github.com/ageitgey/face_recognition>`__ library. Before
you try and use face recognition, please make sure you did a
``sudo -H pip3 install face_recognition`` The reason this is not
automatically done during setup is that it installs a lot of
dependencies that takes time (including dlib) and not everyone wants it.

.. sidebar:: Face recognition limitations

        Don't expect magic with overhead cameras. This library requires a
        reasonable face orientation (works for front facing, or somewhat side
        facing poses) and does not work for full profiles or completely overhead
        faces. Take a look at the `accuracy
        wiki <https://github.com/ageitgey/face_recognition/wiki/Face-Recognition-Accuracy-Problems>`__
        of this library to know more about its limitations. Also note that I found `cnn` mode is much more accurage than `hog` mode. However, `cnn` comes with a speed and memory tradeoff.

Using the right face recognition modes
'''''''''''''''''''''''''''''''''''''''

- Face recognition uses dlib. Note that in ``objectconfig.ini`` you have two options of face detection/recognition. Dlib has two modes of operation (controlled by ``face_model``). Face recognition works in two steps:
  - A: Detect a face
  - B: Recognize a face

``face_model`` affects step A. If you use ``cnn`` as a value, it will use a DNN to detect a face. If you use ``hog`` as a value, it will use a much faster method to detect a face. ``cnn`` is *much* more accurate in finding faces than ``hog`` but much slower. In my experience, ``hog`` works ok for front faces while ``cnn`` detects profiles/etc as well. 

Step B kicks in only after step A succeeds (i.e. a face has been detected). The algorithm used there is common irrespective of whether you found a face via ``hog`` or ``cnn``.

Configuring face recognition directories
''''''''''''''''''''''''''''''''''''''''''

-  Make sure you have images of people you want to recognize in
   ``/var/lib/zmeventnotification/known_faces``
- You can have multiple faces per person
- Typical configuration:

:: 

  known_faces/
    +----------bruce_lee/
                +------1.jpg
                +------2.jpg
    +----------david_gilmour/
            +------1.jpg
            +------img2.jpg
            +------3.jpg
    +----------ramanujan/
            +------face1.jpg
            +------face2.jpg


In this example, you have 3 names, each with different images.

- It is recommended that you now train the images by doing:

::

  sudo -u www-data /var/lib/zmeventnotification/bin/zm_train_faces.py


- Note that you do not necessarily have to train it first but I highly recommend it. When detection runs, it will look for the trained file and if missing, will auto-create it. However, detection may also load yolo and if you have limited GPU resources, you may run out of memory when training. 

-  When face recognition is triggered, it will load each of these files
   and if there are faces in them, will load them and compare them to
   the alarmed image

known faces images
''''''''''''''''''
-  Make sure the face is recognizable
-  crop it to around 800 pixels width (doesn't seem to need bigger
   images, but experiment. Larger the image, the larger the memory
   requirements)
- crop around the face - not a tight crop, but no need to add a full body. A typical "passport" photo crop, maybe with a bit more of shoulder is ideal.


Performance comparison
~~~~~~~~~~~~~~~~~~~~~~

CPU:  Intel Xeon 3.16GHz 4Core machine, with 32GB RAM
GPU: GeForce 1050Ti

General Observations
^^^^^^^^^^^^^^^^^^^^^^^
- Load time of the model is generally larger than detection time, especially felt on a GPU, where detection time is short
- Detection speeds up greatly if you use the same loaded model for subsequent detections. If you are using local detections (i.e. you don't have ml_gateway enabled in objectconfig.ini) then you are essentially exiiting the process each time an image needs to be detected and the DNN is reloaded each time. Even if you take out the model load time, given the DNN is re-initialized, your image is treated as the 'first image' to detect and performance will be lower than when using mlapi because the DNN is reused for subsequent images.
- In general, the detection speed varies between runs, as you see below, at least using local detections.

GPU Performance benchmarking, using an image with 1 person (face+object detection) on my 1050Ti:
(Note in the remote detection case, I am running mlapi on the same system, so same specs)

::

  ** With GPU and local detection (Run 1) **

  02/13/20 16:15:52 zmesdetect_m2[7494] DBG face_train.py:19 [Face Recognition library load time took: 959.26 milliseconds]
  02/13/20 16:15:54 zmesdetect_m2[7494] DBG face.py:87 [Finding faces took 617.892 milliseconds]
  02/13/20 16:15:55 zmesdetect_m2[7494] DBG face.py:92 [Computing face recognition distances took 504.214 milliseconds]
  02/13/20 16:15:55 zmesdetect_m2[7494] DBG face.py:103 [Matching recognized faces to known faces took 1.432 milliseconds]
  02/13/20 16:15:55 zmesdetect_m2[7494] DBG yolo.py:79 [YOLO initialization (loading model from disk) took: 415.967 milliseconds]
  02/13/20 16:15:58 zmesdetect_m2[7494] DBG yolo.py:91 [YOLO detection took: 275.253 milliseconds]
  02/13/20 16:15:59 zmesdetect_m2[7494] DBG yolo.py:122 [YOLO NMS filtering took: 2.467 milliseconds]

  ** With GPU and local detection (Run 2, same image) **
  02/13/20 16:16:52 zmesdetect_m2[7643] DBG face_train.py:19 [Face Recognition library load time took: 949.845 milliseconds]
  02/13/20 16:16:54 zmesdetect_m2[7643] DBG face.py:87 [Finding faces took 663.26 milliseconds]
  02/13/20 16:16:55 zmesdetect_m2[7643] DBG face.py:92 [Computing face recognition distances took 517.721 milliseconds]
  02/13/20 16:16:55 zmesdetect_m2[7643] DBG face.py:103 [Matching recognized faces to known faces took 1.257 milliseconds]
  02/13/20 16:16:55 zmesdetect_m2[7643] DBG yolo.py:79 [YOLO initialization (loading model from disk) took: 416.757 milliseconds]
  02/13/20 16:16:59 zmesdetect_m2[7643] DBG yolo.py:91 [YOLO detection took: 189.495 milliseconds]
  02/13/20 16:16:59 zmesdetect_m2[7643] DBG yolo.py:122 [YOLO NMS filtering took: 1.66 milliseconds]

  ** With GPU and local detection (Run 3, same image) **
  02/13/20 16:17:28 zmesdetect_m2[7747] DBG face_train.py:19 [Face Recognition library load time took: 997.392 milliseconds]
  02/13/20 16:17:31 zmesdetect_m2[7747] DBG face.py:87 [Finding faces took 700.605 milliseconds]
  02/13/20 16:17:31 zmesdetect_m2[7747] DBG face.py:92 [Computing face recognition distances took 575.662 milliseconds]
  02/13/20 16:17:31 zmesdetect_m2[7747] DBG face.py:103 [Matching recognized faces to known faces took 1.161 milliseconds]
  02/13/20 16:17:32 zmesdetect_m2[7747] DBG yolo.py:79 [YOLO initialization (loading model from disk) took: 372.729 milliseconds]
  02/13/20 16:17:35 zmesdetect_m2[7747] DBG yolo.py:91 [YOLO detection took: 99.312 milliseconds]
  02/13/20 16:17:35 zmesdetect_m2[7747] DBG yolo.py:122 [YOLO NMS filtering took: 1.619 milliseconds]

  ** With GPU and local detection (Run 4, same image) **

  02/13/20 16:18:37 zmesdetect_m2[8438] DBG face_train.py:19 [Face Recognition library load time took: 26.514 milliseconds]
  02/13/20 16:18:40 zmesdetect_m2[8438] DBG face.py:87 [Finding faces too 819.668 milliseconds]
  02/13/20 16:18:40 zmesdetect_m2[8438] DBG face.py:92 [Computing face recognition distances took 532.882 milliseconds]
  02/13/20 16:18:40 zmesdetect_m2[8438] DBG face.py:103 [Matching recognized faces to known faces took 1.155 milliseconds]
  02/13/20 16:18:41 zmesdetect_m2[8438] DBG yolo.py:79 [YOLO initialization (loading model from disk) took: 475.909 milliseconds]
  02/13/20 16:18:44 zmesdetect_m2[8438] DBG yolo.py:91 [YOLO detection took: 385.332 milliseconds]
  02/13/20 16:18:44 zmesdetect_m2[8438] DBG yolo.py:122 [YOLO NMS filtering took: 2.153 milliseconds]


  ** With GPU and remote detection via MLAPI (Run 1) **
  DEBUG: Finding faces took 410.292 milliseconds
  DEBUG: Computing face recognition distances took 19.237 milliseconds
  DEBUG: Matching recognized faces to known faces took 0.942 milliseconds
  DEBUG: YOLO detection took: 631.454 milliseconds
  DEBUG: YOLO NMS filtering took: 1.612 milliseconds

  ** With GPU and remote detection via MLAPI (Run 2, same image) **
  DEBUG: Finding faces took 454.663 milliseconds
  DEBUG: Computing face recognition distances took 19.888 milliseconds
  DEBUG: Matching recognized faces to known faces took 0.996 milliseconds
  DEBUG: YOLO detection took: 63.139 milliseconds
  DEBUG: YOLO NMS filtering took: 1.992 milliseconds

  ** With GPU and remote detection via MLAPI (Run 3, same image) **
  DEBUG: Finding faces took 454.351 milliseconds
  DEBUG: Computing face recognition distances took 19.684 milliseconds
  DEBUG: Matching recognized faces to known faces took 1.022 milliseconds
  DEBUG: YOLO detection took: 63.935 milliseconds
  DEBUG: YOLO NMS filtering took: 1.779 milliseconds

  ** With GPU and remote detection via MLAPI (Run 4, different image) **
  DEBUG: Finding faces took 464.449 milliseconds
  DEBUG: Computing face recognition distances took 20.482 milliseconds
  DEBUG: Matching recognized faces to known faces took 1.173 milliseconds
  DEBUG: YOLO detection took: 64.402 milliseconds
  DEBUG: YOLO NMS filtering took: 3.784 milliseconds


Manually testing if detection is working well
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

You can manually invoke the detection module to check if it works ok:

.. code:: bash

    ./sudo -u www-data /var/lib/zmeventnotification/bin/zm_detect.py --config /etc/zm/objectconfig.ini  --eventid <eid> --monitorid <mid>

The ``--monitorid <mid>`` is optional and is the monitor ID. If you do
specify it, it will pick up the right mask to apply (if it is in your
config)


**STEP 1: Make sure the scripts(s) work** 

- Run the python script manually to see if it works (refer to sections above on how to run them manually) 
- ``./zm_event_start.sh <eid> <mid>`` --> make sure it
  downloads a proper image for that eid. Make sure it correctly invokes
  detect.py If not, fix it. (``<mid>`` is optional and is used to apply a
  crop mask if specified) 
- Make sure the ``image_path`` you've chosen in the config file is WRITABLE by www-data (or apache) before you move to step 2

**STEP 2: run zmeventnotification in MANUAL mode** 

- ``sudo zmdc.pl stop zmeventnotification.pl`` 
- change console_logs to yes in ``zmeventnotification.ini``
-  ``sudo -u www-data ./zmeventnotification.pl  --config ./zmeventnotification.ini``
-  Force an alarm, look at logs

**STEP 3: integrate with the actual daemon** 
- You should know how to do this already

Questions
~~~~~~~~~~~
See :doc:`hooks_faq`