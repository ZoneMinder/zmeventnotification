Breaking Changes
----------------

Version 4.4 onwards
~~~~~~~~~~~~~~~~~~~~
- If you are using picture messaging, then the URL format has changed. Please REMOVE ``&username=<user>&password=<passwd>`` from the URL and put them into the ``picture_portal_username`` and ``picture_portal_password`` fields respectively


Version 4.1 onwards
~~~~~~~~~~~~~~~~~~~~
- Hook versions will now always be ``<ES version>.x``, so in this case ``4.1.x``
- Hooks have now migrated to using a `proper python ZM logger module <https://pypi.org/project/pyzmutils/>`__ so it better integrates with ZM logging 
- To view detection logs, you now need to follow the standard ZM logging process. See :ref:`hooks-logging` documentation for more details)
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
