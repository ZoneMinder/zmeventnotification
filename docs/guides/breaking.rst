Breaking Changes
----------------

Version 5.16.0 onwards
~~~~~~~~~~~~~~~~~~~~~~~~~
- To help with this 'big bad breaking change', I've provided an upgrade script.
  Run it by invoking ``hook/config_upgrade.py -c /etc/zm/objectconfig.ini`` and
  inspect results before overwriting your old config.
 
- This is going to be a big bad breaking change release, but continues the path
  to unification between various components I've developed.
- All the ml code has now moved to pyzm and both local hook and mlapi use pyzm. This means
  when I update ml code, both systems get it right always
- This version also supports Google Coral Edge TPU
- Several ``objectconfig.ini`` attributes have been replaced and some removed towards
  this unification goal:

  - ``models`` is now ``detection_sequence``
  - ``yolo`` is no longer used. Instead ``object`` is used. ``object`` could be multiple
    object detection techniques, yolo or otherwise.
  - ``[ml]`` is now ``[remote]``
  - ``[object]`` is a new section, which contains two new attributes:

    - ``object_framework`` which can be ``opencv`` or   ``coral_edgetpu``
    - ``object_processor`` which can be ``cpu``, ``gpu`` or ``tpu``

  - ``yolo_min_confidence``  is now ``object_min_confidence``
  - ``config``, ``weights``, ``labels`` are now ``object_config``, ``object_weights`` and ``object_labels`` respectively.
  - None of the ``tiny_`` attributes exist anymore. Simply switch weights, labels and config files to switch between full and tiny
  - ``yolo_type`` doesn't exist anymore (as ``tiny_`` attributes are removed, so it doesn't make sense)
  - ``alpr_pattern`` is now ``alpr_detection_pattern``
  - ``detect_pattern`` no longer exists. You now have a per detection type pattern, which allows
    you to specify patterns based on the detection type:

    - ``object_detection_pattern`` - for all objects
    - ``alpr_detection_pattern`` - for for license plates
    - ``face_detection_pattern`` - for all faces detected


Version 5.15.7 onwards
~~~~~~~~~~~~~~~~~~~~~~~~~~~~
- The ``<>/models/tinyyolo`` directory is now ``<>/models/tinyyolov3``.
  ``install.sh`` will automatically move it, but remember to change your
  ``objectonfig.ini`` path if you are using tiny yolo.

- You now have an option to use the new Tiny Yolo V4 models which will be 
  automatically downloaded unless you disabled it (You'll need OpenCV master
  as of Jul 11, 2020 as support for it was only merged 6 days ago)

- A new attribute, ``max_object_area`` has been introduced in ``objectconfig.ini``.
  This specifies the largest area a detected object should take inside the image. 
  You can keep it as a % or px value. Remember the image is resized to 416x416. better
  to keep in %

Version 5.15.6 onwards
~~~~~~~~~~~~~~~~~~~~~~~~~
- I got lazy with 5.15.5. There were some errors that I fixed post 5.15
  which I 'post-pushed' into 5.15.5. It is possible you installed 5.15.5 and
  don't have these fixes. In other words, if your 5.15.5 is broken, Please
  upgrade.

- In this release, I've also taken a necessary step towards model naming 
  normalization. Basically, ``Yolo`` models are now ``YoloV3`` and ``CSPN`` 
  is now ``Yolov4``. This is because this is the terminology `Alexey <https://github.com/AlexeyAB/darknet>`__ has started
  using in his repo. This means you will have to change your ``objectconfig.ini`` and align it with
  the same ``objectconfig.ini`` provided in this repo. I've also normalized the names
  of the config, weights and name files for each model. The short of all of this is, look under
  the ``[yolo]`` section of the sample config and replace your current yolo paths.
  Note that I assume you use ``install.sh`` to install. If not, you'll have to manually
  rename the old model names to the new ones.

- If you plan to use YoloV4 (full or Tiny) the minimum version requirement is the version *after* 4.3.0.
  As of Jul 11,2020, that is the master branch of openCV as 4.3.0 is the latest stable version.
  The updated version of YoloV4 that requires certain functions that were committed on Apr 30.
  See `here <https://github.com/opencv/opencv/issues/17148>`__. So if you suddently see an error like:
  ``Unsupported activation: mish in function 'ReadDarknetFromCfgStream'`` popping up with YoloV4, 
  that is a sign that you need to get a later version of OpenCV. Note that TinyYoloV4 was merged after Jul 6,
  so if you get errors with TinyYoloV4, you'll need to upgrade Open CV master.


Version 5.15.5 onwards
~~~~~~~~~~~~~~~~~~~~~~~~
- ``zmeventnotification.ini`` has a new attribute, ``topic`` under ``[mqtt]``
  which lets you set the topic name for the messages

- ``objectconfig.ini`` has a new attribute, ``only_triggered_zm_zones``. When set to yes,
  this will remove objects that don't fall into zones that ZM detects motion in.
  Make sure you read the comments in ``objectconfig.ini`` above the attribute
  to understand its limitations


Version 5.14.4 onwards
~~~~~~~~~~~~~~~~~~~~~~~
- Added ability for users to PR contrib modules
  See :doc:`guides/contrib_guidelines`
- ``zmeventnotification.ini`` adds two new attributes that makes it simpler for users
  to keep object detection plugin hooks intact *and also* trigger their own scripts 
  for housekeeping. See the ini script for documentation on ``event_start_hook_notify_userscript``
and ``event_end_hook_notify_userscript``


Version 5.13.3 onwards
~~~~~~~~~~~~~~~~~~~~~~~~~~
- New attribute ``es_debug_level`` in ``zmeventnotification.ini`` that controls debug level verbosity. Default is ``2``
- New CSPNet support with ResNeXt (requires OpenCV 4.3 or above)
  - Note that this requires a **manual model download** as the model is in a google drive link and all automated download scripts are hacks that stop working after a while.
- You can now choose which models to download as part of ``./install.sh``. See :ref:`install_specific_models`


Version  5.11 onwards
~~~~~~~~~~~~~~~~~~~~~~

- If you are using platerecognition.com local SDK for ALPR, their SDK and cloud versions have slightly different API formats. There is a new attribute called ``alpr_api_type`` in ``objectconfig.ini`` that should be set to ``local`` to handle this. 
- ``skip_monitors`` in ``zmeventnotification.ini`` is now called ``hook_skip_monitors`` to correctly reflect this only means hooks will be skipped for these monitors. A new attribute ``skip_monitors`` has been added that controls which monitors the ES will skip completely (That is, no analysis /otifications at all for these monitors)
- Added support for live animations as part of push messages. This requires an upgraded zmNinja app (``1.3.0.91`` or above) as well as ZoneMinder master (1.35) as of Mar 17 2020. Without these two updates, live notifications will not work. Specifically:
  - This introduces a new section in ``objectconfig.ini`` called ``[animation]``. Please read the config for more details.
  - You are also going to have to re-run ``install.sh`` to install new dependencies

Version 5.9.9 onwards
~~~~~~~~~~~~~~~~~~~~~~~~~
- You can now hyper charge your push notifications, including getting desktop notifications. See below
- I now support 3rd party push notification systems. A popular one is `pushover <http://pushover.net>`__ that a lot of people seem to use for customizing the quality of push notifications, including critical notifications, quiet time et. al. This adds the following parameters:
  - A new section called ``[push]`` in ``zmeventnotification.ini``  that adds two new attributes: ``use_api_push`` and ``api_push_script``
  - I've provided a sample push script that supports pushover. This gets automatically installed when you use ``install.sh`` into ``/var/lib/zmeventnotification/bin/pushapi_pushover.py``
  - This also addes a new channel type called ``api`` to the pre-existing ``fcm,web,mqtt`` set.
  - You are of course, encouraged to write your own 3rd party plugins for push and PR back to the project.
  - Read more in `this article <https://medium.com/zmninja/hypercharging-push-notifications-with-pushover-and-others-23ed9ab706>`__

Version 5.7.7 onwards
~~~~~~~~~~~~~~~~~~~~~~~
- For those who are happy to use the legacy openALPR self compiled version for license plate detection that does not use DNNs, I support that. This adds new parameters to `objectconfig.ini`. See objectconfig.ini for new parameters under the "If you are using OpenALPR command line" section.

Version 5.7.4 onwards
~~~~~~~~~~~~~~~~~~~~~~~
- I know support the new OpenCV 4.1.2 GPU backend support for CUDA. This will only work if you are on OpenCV 4.1.2 and have compiled it correctly to use CUDA and are using the right architecture. 
  - This adds a new attribute ``use_opencv_dnn_cuda`` in ``objectconfig.ini`` which by default is ``no``. Please read the comments in ``objectconfig.ini`` about how to use this.
- The ES supports a control channel using which you can control its behavior remotely
  - This adds new attributes ``use_escontrol_interface``, ``escontrol_interface_file`` and ``escontrol_interface_password`` to ``zmeventnotification.ini``. Read more about it :ref:`escontrol_interface`.
- If you are using face recognition, you now have the option of automatically saving unknown faces to a specific folders. That way it's easy for you to review them later and retrain your known faces.
  - This introduces the following new attributes to ``objectconfig.ini``: ``save_unknown_faces``, ``save_unknown_faces_leeway_pixels`` and ``unknown_images_path``. Their documentation is part of ``objectconfig.ini``
- The detection script(s) now attach a JSON payload of the detected objects along with the text, separated by ``--SPLIT--``. If you are hacking your own scripts, you need to handle this. The ES automatically handles it when sending notifications.

Version 5.2 onwards
~~~~~~~~~~~~~~~~~~~~
- `use_hooks` is a new attribute that controls whether hooks will be used or not
- `send_event_end_notification` is a new attribute that controls whether end notifications are sent 

Version 5.0 onwards
~~~~~~~~~~~~~~~~~~~~~

- ``install.sh`` no longer tries to install opencv on its own. You will have to install ``opencv`` and ``opencv-contrib`` on your own. See install instructions in :doc:`hooks`.

- The ``hook_script`` attribute is deprecated. You now have ``hook_on_event_start`` and ``hook_on_event_end`` which lets you invoke different scripts when an event starts or ends. You also have the concepts of channels, that allows you to decide whether to send a notification even if hooks don't return anything. Read up about ``notify_on_hook_success`` and ``notify_on_hook_fail`` in  ``zmeventnotification.ini`` 

- Now that we support pre/post event hooks, the script names have changed too (``zm_detect_wrapper.sh`` is ``zm_event_start.sh`` and we have a new script called ``zm_event_end.sh`` that is really just a dummy script. Change it to what you need to do at the end of an event, if you enable event end notifications)

- You can now offload the entire machine learning processes to a remote server. All you need to do is to use ``ml_gateway`` and related options in ``objectconfig.ini``. The "ML gateway" is `my mlapi project <https://github.com/pliablepixels/mlapi>`__

- The ES now supports a ``restart_interval`` config item in ``zmeventnotification.ini``. If not 0, this will restart the ES after those many seconds (example ``7200`` is 2 hours). This may be needed if you find the ES locking up after a few hours. I think 5.0 resolves this locking issue (see `this issue <https://github.com/pliablepixels/zmeventnotification/issues/175>`__) but if it doesn't use this, umm, hack for now.


Version 4.6 onwards
~~~~~~~~~~~~~~~~~~~~
- If you are using hooks, make sure you run ``sudo ./install.sh`` again - it will create additional files in ``/var/lib/zmeventnotification``
- The hook files ``detect.py`` and ``detect_wrapper.sh`` are now called ``zm_detect.py`` and ``zm_detect_wrapper.sh``.  Furthermore, these scripts no longer reside in ``/usr/bin``. They will now reside in ``/var/lib/zmeventnotification/bin``. I suppose I did not need to namespace and move, but I thought of the latter after I did the namespace changing.
- If you are using face recognition, 4.6.1 and above now allow multiple faces per person. Note that it is recommended you train them before you run detection. See the documentation for it in :doc:`hooks`.


Version 4.4 onwards
~~~~~~~~~~~~~~~~~~~~
- If you are using picture messaging, then the URL format has changed. Please REMOVE ``&username=<user>&password=<passwd>`` from the URL and put them into the ``picture_portal_username`` and ``picture_portal_password`` fields respectively


Version 4.1 onwards
~~~~~~~~~~~~~~~~~~~~
- Hook versions will now always be ``<ES version>.x``, so in this case ``4.1.x``
- Hooks have now migrated to using a `proper python ZM logger module <https://pypi.org/project/pyzmutils/>`__ so it better integrates with ZM logging 
- To view detection logs, you now need to follow the standard ZM logging process. See :ref:`es-hooks-logging` documentation for more details)
- You no longer have to manually install python requirements, the setup process should automatically install them
- If you are using MQTT and your  ``MQTT:Simple`` library was installed a while ago, you may need to update it. A new ``login`` method was added
  to that library on Dec 2018 which is required (`ref <https://github.com/Juerd/Net-MQTT-Simple/blob/cf01b43c27893a07185d4b58ff87db183d08b0e9/Changes#L21>`__)


Version 3.9 onwards
~~~~~~~~~~~~~~~~~~~~
- Hooks now add ALPR, so you need to run `sudo -H pip install -r requirements.txt` again
- See modified objectconfig.ini if you want to add ALPR. Currently works with platerecognizer.com, so you will need an API key. See hooks docs for more info

Version 3.7 onwards
~~~~~~~~~~~~~~~~~~~
- There were some significant changes to ZM (will be part of 1.34), which includes migration to Bcrypt for passwords. Changes were made to support Bcrypt, which means you will have to add additional libraries. See the installation guide.

version 3.3 onwards
~~~~~~~~~~~~~~~~~~~

- Please use ``yes`` or ``no`` instead of ``1`` and ``0`` in ``zmeventnotification.ini`` to maintain consistency with ``objectconfig.ini``
- In ``zmeventnotification.ini``, ``store_frame_in_zm`` is now ``hook_pass_image_path``

version 3.2 onwards
~~~~~~~~~~~~~~~~~~~

- Changes in paths for everything. - event server config file now defaults to ``/etc/zm`` 
- hook config now defaults to ``/etc/zm`` 
- Push token file now defaults to ``/var/lib/zmeventnotification/push`` 
- all object detection data files default to ``/var/lib/zmeventnotification``
- If you are migrating from a previous version: 
        - Make a copy of your ``/etc/zmeventnotification.ini`` and ``/var/detect/objectconfig.ini`` (if you are using hooks) 
        - Run ``sudo -H ./install.sh`` again inside the repo, let it set up all the files 
        - Compare your old config files to the news ones at ``/etc/zm`` and make necessary changes 
        - Make sure everything works well 
        - You can now delete the old ``/var/detect`` folder as well as ``/etc/zmeventnotification.ini`` 
        - Run zmNinja again to make sure its token is registered in the new tokens file (in ``/var/lib/zmeeventnotification/push/tokens.txt``)
