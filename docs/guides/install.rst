
Installation of the Event Server (ES)
--------------------------------------

.. _third_party_dockers:

3rd party dockers 
~~~~~~~~~~~~~~~~~~

I don't maintain docker images, so please don't ask me any questions about docker environments. There are others who maintain docker images. 
I have no affiliation with any of them. Feel free to explore the various options below, but please don't ask me about them. I've also not tried any of these 
dockers.

- Alex's repo (in progress): `Various ZM configurations, currently ZM and ZM+ES (no hooks) <https://github.com/zoneminder-containers>`__ 
- Vangorra's repo:`A docker container with ZM+ES+hooks+MLAPI <https://github.com/vangorra/zoneminder-zmeventnotification>`__
- dlandon's repo: `A ZM+ES+hooks container (may not be free/maintained anymore) <https://github.com/dlandon/zoneminder.machine.learning>`__
- The Moosman's  repo: `A docker container for MLAPI <https://github.com/themoosman/mlapi>`__

If there are other repositories you are aware of that work well, let me know.

If you are using docker images, the next section does not apply.

Clone the repo
~~~~~~~~~~~~~~~~~

I'd recommend users download the latest stable release. Starting version 4.5 I have started tagging releases that are rested. The master branch will always be 'cutting-edge'.

To clone the latest stable release:
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

::

  git clone https://github.com/zoneminder/zmeventnotification.git
  cd zmeventnotification
  # repeat these two steps each time you want to update to the latest stable
  git fetch --tags
  git checkout $(git describe --tags $(git rev-list --tags --max-count=1))

To clone master:
^^^^^^^^^^^^^^^^^

::

  git clone https://github.com/zoneminder/zmeventnotification.git
  # repeat these two steps each time you want to update
  git checkout master # only needed if you are on some other branch later
  git pull


Configure the ini files
~~~~~~~~~~~~~~~~~~~~~~~~~~~
-  Edit ``zmeventnotification.ini`` to your liking. More details about
   various parts of the configuration are explained later in this readme
-  If you are behind a firewall, make sure you enable port ``9000``,
   TCP, bi-directional (unless you changed the port in the code)
-  If you are _not_ using machine learning hooks, make sure you comment out the
   ``hook_script`` attribute in the ``[hook]`` section of the ini file or 
   you will see errors and you will not receive push
-  We now need to install a bunch of dependencies (as described below)

Install Dependencies
~~~~~~~~~~~~~~~~~~~~

Note that I assume you have other development packages already installed
like ``make``, ``gcc`` etc as the plugins may require them. The
following perl packages need to be added (these are for Ubuntu - if you
are on a different OS, you'll have to figure out which packages are
needed - I don't know what they might be)

(**General note** - some users may face issues installing dependencies
via ``perl -MCPAN -e "Module::Name"``. If so, its usually more reliable
to get into the CPAN shell and install it from the shell as a 2 step
process. You'd do that using ``sudo perl -MCPAN -e shell`` and then
whilst inside the shell, ``install Module::Name``)

-  ``Crypt::MySQL`` (if you have updated to ZM 1.34, this is no longer needed)
-  ``Net::WebSocket::Server``
-  ``Config::IniFiles`` (you may already have this installed)
-  ``Crypt::Eksblowfish::Bcrypt`` (if you have updated to ZM 1.34, you will already have this)
-  ``Time::Piece`` for parsing ES rules

Installing these dependencies is as simple as:

::

    sudo perl -MCPAN -e "install Crypt::MySQL"
    sudo perl -MCPAN -e "install Config::IniFiles"
    sudo perl -MCPAN -e "install Crypt::Eksblowfish::Bcrypt"
   
If after installing them you still see errors about these libraries
missing, please launch a CPAN shell - see General Note above.

If you face issues installing Crypt::MySQL try this instead: (Thanks to
aaronl)

::

    sudo apt-get install libcrypt-mysql-perl
    
If you face issues installing Crypt::Eksblowfish::Bcrypt, this this instead:

::

    sudo apt-get install libcrypt-eksblowfish-perl


If there are issues installing Config::IniFiles and the errors are
related to Module::Build missing, use following command to get this
module in debian based systems and install Config::IniFiles again.

::

    sudo apt-get install libmodule-build-perl

Next up install WebSockets

::

    sudo apt install libyaml-perl
    sudo apt install make
    sudo apt install libprotocol-websocket-perl
    sudo perl -MCPAN -e "install Net::WebSocket::Server"

Then, you need JSON.pm installed. It's there on some systems and not on
others In ubuntu, do this to install JSON:

::

    sudo apt-get install libjson-perl

Get HTTPS library for LWP:

::

    sudo apt-get install liblwp-protocol-https-perl

    or 

    perl -MCPAN -e "install LWP::Protocol::https"

If you want to enable MQTT:

::

    perl -MCPAN -e "install Net::MQTT::Simple"


If you are setting up MQTT:

 - A minimum version of MQTT 3.1.1 is required
 - If your ``MQTT:Simple`` library was installed a while ago, you may need to update it. A new ``login`` method was added
   to that library on Dec 2018 which is required (`ref <https://github.com/Juerd/Net-MQTT-Simple/blob/cf01b43c27893a07185d4b58ff87db183d08b0e9/Changes#L21>`__)

Note that starting 1.0, we also use ``File::Spec``, ``Getopt::Long`` and
``Config::IniFiles`` as additional libraries. My ubuntu installation
seemed to include all of this by default (even though
``Config::IniFiles`` is not part of base perl).

If you get errors about missing libraries, you'll need to install the
missing ones like so:

::

    perl -MCPAN -e "install XXXX" # where XXX is Config::IniFiles, for example

If you are also planning on using the machine learning hooks, you will need to make sure you have Python3 and pip3 installed and working properly. Refer to your OS package documentation on how to get Python3 and pip3. 

Configure SSL certificate (Generate new, or use ZoneMinder certs if you are already using HTTPS)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**NOTE:** If you plan on using picture messaging in zmNinja, then you cannot use self signed certificates. You will need to generate a proper certificate. LetsEncrypt is free and perfect for this.

If you are using secure mode (default) you **also need to make sure you
generate SSL certificates otherwise the script won't run** If you are
using SSL for ZoneMinder, simply point this script to the certificates.

If you are not already using SSL for ZoneMinder and don't have
certificates, generating them is as easy as:

(replace ``/etc/zm/apache2/ssl/`` with the directory you want the
certificate and key files to be stored in)

::

    sudo openssl req -x509 -nodes -days 4096 -newkey rsa:2048 -keyout /etc/zm/apache2/ssl/zoneminder.key -out /etc/zm/apache2/ssl/zoneminder.crt

It's **very important** to ensure the ``Common Name`` selected while
generating the certificate is the same as the hostname or IP of the
server. For example if you plan to access the server as
``myserver.ddns.net`` Please make sure you use ``myserver.ddns.net`` as
the common name. If you are planning to access it via IP, please make
sure you use the same IP.

Once you do that please change the following options in the config file
to point to your SSL certs/keys:

::

    [ssl]
    cert = /etc/zm/apache2/ssl/zoneminder.crt
    key = /etc/zm/apache2/ssl/zoneminder.key

IOS Users
^^^^^^^^^

On some IOS devices and when using self signed certs, I noticed that
zmNinja was not able to register with the event server when it was using
WSS (SSL enabled) and self-signed certificates. To solve this, I had to
email myself the zoneminder certificate (``zoneminder.crt``) file and
install it in the phone. Why that is needed only for WSS and not for
HTTPS is a mystery to me. The alternative is to run the eventserver in
WS mode by disabling SSL.


Install the server (optionally along with hooks) 
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**NOTE** : By default ``install.sh`` moves the ES script to ``/usr/bin``. 
If your ZM install is elsewhere, like ``/usr/local/bin`` please modify the ``TARGET_BIN`` variable
in ``install.sh`` before executing it.

-  You can now move the ES to the right place by simply doing
   ``sudo ./install.sh`` and following prompts. Other options are below:
-  Execute ``sudo ./install.sh --no-install-hook`` to move the ES to the
   right place without installing machine learning hooks



Update the configuration files
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

When you install the ES, it comes with default configuration files. They key files
are:

- ``/etc/zm/zmeventnotification.ini`` - various parameters that control the ES
- ``/etc/zm/objectconfig.ini`` - various parameters that control the machine learning hooks
- ``/etc/zm/secrets.ini`` - a common key/value mapping file where you store your personal configurations

You **always** have to modify ``/etc/zm/secrets.ini`` to your server settings. Please review
the keys and update them with your settings. At the least, you will need to modify:

- ``ZM_USER`` - the username used to log into your ZM web console
- ``ZM_PASSWORD`` - the password for your ZM web console
- ``ZM_PORTAL`` - the URL for your ZM instance (typically ``https://<domain>/zm``)
- ``ZM_API_PORTAL`` - the URL for your ZM API instance (typically ``https://<portal>/api``)
- ``ES_CERT_FILE`` and ``ES_KEY_FILE`` - the certificates to use if you are using HTTPS

Next, You can/should run it manually at first to check if it works

Optional but Recommended: Making sure everything is running (in manual mode)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

-  Start the event server manually first using
   ``sudo -u www-data /usr/bin/zmeventnotification.pl --debug``
   (Note that if you omit ``--config`` it will look for
   ``/etc/zm/zmeventnotification.ini`` and if that doesn't exist, it
   will use default values) and make sure you check syslogs to ensure
   its loaded up and all dependencies are found. If you see errors, fix
   them. Then exit and follow the steps below to start it along with
   Zoneminder. Note that the ``-u www-data`` runs this command with the
   user id that apache uses (in some systems this may be ``apache`` or
   similar). It is important to run it using the same user id as your
   webserver because that is the permission zoneminder will use when run
   as a daemon mode.

-  Its is HIGHLY RECOMMENDED that you first start the event server
   manually from terminal, as described above and not directly dive into
   daemon mode (described below) and ensure you inspect syslog to
   validate all logs are correct and THEN make it a daemon in
   ZoneMinder. If you don't, it will be hard to know what is going
   wrong. See :ref:`this section <debug_reporting_es>` later that describes how to make sure its all working fine
   from command line.

Making sure the ES gets auto-started when ZM starts
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

-  Go to your web interface, and go to
   ``Options->Systems`` and enable ``OPT_USE_EVENTNOTIFICATION`` and you
   are all set.
- If you plan on using the machine learning hooks, there is more work to do. Please refer to :ref:`hooks_install`.

**The rest of this section is NOT NEEDED for 1.32.0 and above!**


Set up logging correctly for troubleshooting
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
For quick debugging, you can just run the ES or hooks manually by adding ``--debug`` but for proper logging,
follow steps :ref:`here <es-hooks-logging>`
