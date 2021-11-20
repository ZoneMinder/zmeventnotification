Configuration Guide
====================
**NOTE:** ``zmeventnotification.ini`` and ``secrets.ini`` are the configuration and secrets file for the Event Server, ``zmeventnotification.ini`` is required for proper operation!


There are two parts to the configuration of this system:

* The Event Notification Server configuration - typically ``/etc/zm/zmeventnotification.ini``
* The Machine Learning Hooks configuration -  typically ``/etc/zm/objdetect.yml`` and/or
  ``/var/lib/zmeventnofication/mlapi/mlapiconfig.yml``

The ES comes with a `sample ES config file <https://github.com/baudneo/zmeventnotification/blob/master/zmeventnotification.ini>`__
which you should customize as you see fit. The sample config file is well annotated, so you really should read the comments to get an
understanding of what each parameter does. Similarly, the ES also comes with a `sample objdetect.yml file <https://github.com/baudneo/blob/zmeventnotification/master/hook/objectconfig.yml>`__
which you should read as well if you are using hooks. If you are using mlapi, read `its config <https://github.com/baudneo/mlapi/blob/master/mlapiconfig.yml>`__.

Secret Tokens - MODIFIED BY NEO ZMES
-------------
**See the .ini files for their example of secrets**

This allows you to easily share your config files without inadvertently sharing your secrets.

Basically, this is how it works:

You add an attribute called ``secrets`` to either/both config files. This points to some filename you have created with tokens. Then you can just use the token name in the config file.

For example, let's suppose we add this to ``/etc/zm/objectconfig.yml``:

::

  # This is an optional file
  # If specified, you can specify tokens with secret values in that file
  # and only refer to the tokens in your main config file ** !SECRETS are now {[SECRETS]} **
  secrets: /etc/zm/zm_secrets.yml

  portal: '{[ZM_PORTAL]}'
  user: '{[ZM_USER]}'
  password: '{[ZM_PASSWORD]}'

And ``/etc/zm/secrets.yml`` contains:

::

  # your secrets file
  ZMES_PICTURE_URL: https://mysecretportal/zm/index.php?view=image&eid=EVENTID&fid=objdetect&width=600
  #ZMES_PICTURE_URL: https://mysecretportal/zm/index.php?view=image&eid=EVENTID&fid=snapshot&width=600
  ZM_USER: myusername
  ZM_PASSWORD: mypassword
  ZM_PORTAL: https://mysecretportal/zm

Then, while parsing the config file, the parser looks for these {[Secrets]} and replaces them with their configured values.

The same concept applies to ``/etc/zm/zmeventnotification.ini`` and ``/var/lib/zmeventnofication/mlapi/mlapiconfig.yml``