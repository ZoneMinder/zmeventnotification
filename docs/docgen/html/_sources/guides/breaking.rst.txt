Breaking Changes
----------------

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
