Machine Learning Hooks FAQ
===========================

I get a segment fault/core dump while trying to use opencv in detection
--------------------------------------------------------------------------
See :ref:`opencv_seg_fault`.


Necessary Reading - Sample Config Files
----------------------------------------
The sample configuration files, `zmeventnotification.ini <https://github.com/pliablepixels/zmeventnotification/blob/master/zmeventnotification.ini>`__ and `objectconfig.ini <https://github.com/pliablepixels/zmeventnotification/blob/master/hook/objectconfig.ini>`__  come with extensive commentary about each attribute and what they do. Please go through them to get a better understanding. Note that most of the configuration attributes in `zmeventnotification.ini` are not related to machine learning, except for the `[hook]` section.

How do the hooks actually invoke object detection?
-----------------------------------------------------

* When the Event Notification Server detects an event, it invokes the script specified in ``event_start_hook``  in your ``zmeventnotification.ini``. This is typically ``/var/lib/zmeventnotification/bin/zm_event_start.sh``

* ``zm_event_start.sh`` in turn invokes ``zm_detect.py`` that does the actual machine learning. Upon exit, it either returns a ``1`` that means object found, or a ``0`` which means nothing found. Based on how you have configured your settings, this information is then stored in ZM and/or pushed to your mobile device as a notification.


How To Debug Issues
---------------------
* Refer to :ref:`hooks-logging`


It looks like when ES invokes the hooks, it misses objects, but when I run it manually, it detects it just fine
------------------------------------------------------------------------------------------------------------------

This is a very common situation and prior to ZM 1.34 there was also a bug. Here is what is likely happening:

* If you have configured ``BESTMATCH`` then the hooks will search for both your "alarmed" frame and the "snapshot" frame for objects. If you have configured ``snapshot``, ``alarm`` or a specfic ``fid=xx`` only that frame will be searched

* An 'alarm' frame is the first frame that caused the motion trigger
* A 'snapshot' frame is the frame with the *highest* score in the event

The way ZM works is that the 'snapshot' frame may keep changing till the full event is over. This is because as event frames are analyzed, if their 'score' is higher than the current snapshot score, the frame is replaced.

Next up, the 'alarm' frame is much more static, but prior to version 1.34, ZM took finite time (typically a few seconds) to actually write the alarmed frame to disk. In 1.34 changes were made to write them as soon as possible, but it may still take some finite time. If the alarm frame is not written by the time the ES requests it, ZM will return the first frame.

What is likely happening in your case is that when the ES invokes the hooks, your snapshot frame is the current frame with the highest score, and your alarmed frame may or may not be written to disk yet. So the hooks run on what is available.

However, when you run it manually later, your snapshot image has likely changed. It is possible as well that your alarmed frame exists now, whereas it did not exist before.

How do I make sure this is what is happening?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
- Enable ``write_debug_image`` in ``objectconfig.ini``. This will create a debug image inside the event path where your event recording is. Take a look at the debug images it creates. Is it the same as the images you see at a later date? If not, you know this is exactly what is happening
- When you run the detection script manually, see if its printing an ``[a]`` or an ``[s]`` before the detected text. The latter means ``snapshot`` and if that is so, the chances are very high this is exactly what the issue is. Incase it prints ``[a]`` it also means the same thing, but the occurrence of this is less than snapshot.

How do I solve this issue?
~~~~~~~~~~~~~~~~~~~~~~~~~~
- If you are running ZM 1.32 or below, upgrade to 1.34 (1.33 master as of Oct 2019). This *should* fix the issue of delayed alarm frame writes
- If you are running ZM 1.32 or below, turning off JPEG store will help. When JPEG store is enabled, snapshots are written later. This bug was fixed in 1.34 (see `this issue <https://github.com/ZoneMinder/zoneminder/issues/2745>`__).
- Add a ``wait: 5`` to that monitor in ``objectconfig.ini`` (again, please read the ini file to understand). This delays hook execution by 5 seconds. The hope here is that the time specified is sufficient for the alarmed frame and the right snapshot to be written to disk
- Fix your zone triggers. This is really the right way. If you use object detection, re-look at how your zone triggers to be able to capture the object of interest as soon as possible. If you do that, chances are high that by the time the script runs, the image containing the object will be written to disk. 


I'm having issues with accuracy of Face Recognition
-----------------------------------------------------
- Use ``cnn`` mode in face recognition. Much slower, but far more accurage than ``hog``
-  Look at debug logs.

   -  If it says "no faces loaded" that means your known images don't
      have recognizable faces
   -  If it says "no faces found" that means your alarmed image doesn't
      have a face that is recognizable
   -  Read comments about ``num_jitters``, ``model``, ``upsample_times``
      in ``objectconfig.ini``

-  Experiment. Read the `accuracy wiki <https://github.com/ageitgey/face_recognition/wiki/Face-Recognition-Accuracy-Problems>`__ link.


.. _local_remote_ml:

Local vs. Remote server for Machine Learning
---------------------------------------------
As of version 5.0.0, you can now comfigure an API gateway for remote machine learning by installing `my mlapi server <https://github.com/pliablepixels/mlapi>`__ on a remote server. Once setup, simply point your ``ml_gateway`` inside ``objectconfig.ini`` to the IP/port of your gateway and make sure ``ml_user`` and ``ml_password`` are the user/password you set up on the API gateway. That's all.

The implementation is a little kludgy, which I'll refine over time. What will now happen is any time ``zm_detect.py`` needs to do object detection or face recognition, it will simply pass on that image to the API Gateway instead of trying to do it locally. This can significantly free up resources in your ZM server that is running the ES.

If you want to know what is kludgy as of today:

- All the machine libraries are still installed locally, even if you only want remote usage (just that local ones will not be used). So its a double install, effectively. The good part of course it you can easily switch between local and remote just by commenting/uncommenting ``ml_api_gateway`` in ``objectconfig.ini``

- The way the local instance (``zm_detect.py``) passes images to the remote API server is clumsy. The image will first be downloaded locally, then sent via multipart/mime/HTTP to the API server and then it will analyze. This makes it easy for me to make sure all the existing options like ``write_debug_images`` and others continue to work locally or remotely. Obviously, a better approach would be just to pass the snapshot/alarm image URLs to the remote API server and have it download it, but this will break some of my existing debug functions. I'll get to it some day.
