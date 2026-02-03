Configuration Guide
====================

All configuration files use **YAML format**. There are two parts to the configuration of this system:

* The Event Notification Server configuration - typically ``/etc/zm/zmeventnotification.yml``
* The Machine Learning Hooks configuration - typically ``/etc/zm/objectconfig.yml``

The ES comes with a `sample ES config file <https://github.com/pliablepixels/zmeventnotification/blob/master/zmeventnotification.example.yml>`__
which you should customize as fit. The sample config file is well annotated, so you really should read the comments to get an
understanding of what each parameter does. Similarly, the ES also comes with a `sample objectconfig.yml file <https://github.com/pliablepixels/zmeventnotification/blob/master/hook/objectconfig.yml>`__
which you should read as well if you are using hooks.

.. note::

    If you are upgrading from an older version that used INI/JSON config files (``zmeventnotification.ini``,
    ``objectconfig.ini``, ``secrets.ini``, ``es_rules.json``), the ``install.sh`` script will automatically
    migrate them to YAML. See :doc:`breaking` for details on the migration.

Secret Tokens
-------------
All the config files have a notion of secrets. Basically, it is a mechanism to separate out your personal passwords and tokens
into a different file from your config file. This allows you to easily share your config files without inadvertently sharing your
secrets.

Basically, this is how it works:

You add a ``secrets`` key in the ``general`` section of either/both config files. This points to some filename you have created with tokens. Then you can just use the token name (prefixed with ``!``) in the config file.

For example, let's suppose we have this in ``/etc/zm/objectconfig.yml``:

::

  general:
    # This is an optional file
    # If specified, you can specify tokens with secret values in that file
    # and only refer to the tokens in your main config file
    secrets: /etc/zm/secrets.yml

    portal: "!ZM_PORTAL"
    user: "!ZM_USER"
    password: "!ZM_PASSWORD"

And ``/etc/zm/secrets.yml`` contains:

::

  secrets:
    ZMES_PICTURE_URL: "https://mysecretportal/zm/index.php?view=image&eid=EVENTID&fid=objdetect&width=600"
    ZM_USER: myusername
    ZM_PASSWORD: mypassword
    ZM_PORTAL: "https://mysecretportal/zm"
    ZM_API_PORTAL: "https://mysecretportal/zm/api"

Then, while parsing the config file every time a value is found that starts with ``!`` that means it's a secret token and the corresponding value from the secrets file will be substituted.

The same concept applies to ``/etc/zm/zmeventnotification.yml``.

**Obviously this means you can no longer have a password beginning with an exclamation mark directly in the config. It will be treated as a secret token**.
To work around this, create a password token in your secrets file and put the real password there.
