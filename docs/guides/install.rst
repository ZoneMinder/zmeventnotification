Installation of the Event Server (ES)
--------------------------------------

Download the repo
~~~~~~~~~~~~~~~~~

-  Clone the project to some directory
   ``git clone https://github.com/pliablepixels/zmeventnotification.git``
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

-  Crypt::MySQL (if you have updated to ZM 1.34, this is no longer needed)
-  Net::WebSocket::Server
-  Config::IniFiles (you may already have this installed)
-  Crypt::Eksblowfish::Bcrypt (if you have updated to ZM 1.34, you will already have this)

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

    sudo apt-get install libyaml-perl
    sudo apt-get install make
    sudo perl -MCPAN -e "install Net::WebSocket::Server"

Then, you need JSON.pm installed. It's there on some systems and not on
others In ubuntu, do this to install JSON:

::

    sudo apt-get install libjson-perl

Get HTTPS library for LWP:

::

    perl -MCPAN -e "install LWP::Protocol::https"

If you want to enable MQTT:

::

    perl -MCPAN -e "install Net::MQTT::Simple"


Some notes on MQTT:

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

Configure SSL certificate (Generate new, or use ZoneMinder certs if you are already using HTTPS)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**NOTE:** If you plan on using picture messaging in zmNinja, then you cannot use self signed certificates. You will need to generate a proper certificate. LetsEncrypt is free and perfect for this.

If you are using secure mode (default) you **also need to make sure you
generate SSL certificates otherwise the script won't run** If you are
using SSL for ZoneMinder, simply point this script to the certificates.

If you are not already using SSL for ZoneMinder and don't have
certificates, generating them is as easy as:

(replace /etc/zm/apache2/ssl/ with the directory you want the
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

Making sure everything is running (in manual mode)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

-  I am assuming you have downloaded the files to your current directory
   in the step below
-  Make sure you do a ``chmod a+x ./zmeventnotification.pl``
-  Start the event server manually first using
   ``sudo -u www-data ./zmeventnotification.pl --config ./zmeventnotification.ini``
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

Install the server (optionally along with hooks) 
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**NOTE** : By default ``install.sh`` moves the ES script to ``/usr/bin``. 
If your ZM install is elsewhere, like ``/usr/local/bin`` please modify the ``TARGET_BIN`` variable
in ``install.sh`` before executing it.

-  You can now move the ES to the right place by simply doing
   ``sudo ./install.sh`` and following prompts. Other options are below:
-  Execute ``sudo ./install.sh --no-install-hook`` to move the ES to the
   right place without installing machine learning hooks
-  In ZM 1.32.0 and above, go to your web interface, and go to
   ``Options->Systems`` and enable ``OPT_USE_EVENTNOTIFICATION`` and you
   are all set.

**The rest of this section is NOT NEEDED for 1.32.0 and above!**

.. deprecated:: 1.32.0

**WARNING** : Do NOT do this before you run it manually as I've
mentioned above to test. Make sure it works, all packages are present
etc. before you add it as a daemon as if you don't and it crashes you
won't know why

(Note if you have compiled from source using cmake, the paths may be
``/usr/local/bin`` not ``/usr/bin``)

-  Edit ``/usr/bin/zmdc.pl`` and in the array ``@daemons`` (starting
   line 89 or so, may change depending on ZM version) add
   ``'zmeventnotification.pl'`` like
   `this <https://gist.github.com/pliablepixels/18bb68438410d5e4b644>`__
-  Edit ``/usr/bin/zmpkg.pl`` and around line 275 (exact line # may
   change depending on ZM version), right after the comment that says
   ``#this is now started unconditionally`` and right before the line
   that says ``runCommand( "zmdc.pl start zmfilter.pl" );`` start
   zmeventnotification.pl by adding
   ``runCommand( "zmdc.pl start zmeventnotification.pl" );`` like
   `this <https://gist.github.com/pliablepixels/b4e4fd38ac526c5c881ee55da05195ff>`__
-  Make sure you restart ZM. Rebooting the server is better - sometimes
   zmdc hangs around and you'll be wondering why your new daemon hasn't
   started
-  To check if its running do a
   ``zmdc.pl status zmeventnotification.pl``

You can/should run it manually at first to check if it works
