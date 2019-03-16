FAQ
===

Machine Learning! Mmm..Machine Learning!
----------------------------------------

Easy. You will first have to read this document to correctly install
this server along with zoneminder. Once it works well, you can explore
how to enable Machine Learning based object detection that can be used
along with ZoneMinder alarms. If you already have this server figured
out, you can skip directly to the machine learning part (:doc:`hooks`)


What is it?
-----------

A WSS (Secure Web Sockets) and/or MQTT based event notification server
that broadcasts new events to any authenticated listeners. (As of 0.6,
it also includes a non secure websocket option, if that's how you want
to run it)

Why do we need it?
------------------

-  The only way ZoneMinder sends out event notifications via event
   filters - this is too slow
-  People developing extensions to work with ZoneMinder for Home
   Automation needs will benefit from a clean interface
-  Receivers don't poll. They keep a web socket open and when there are
   events, they get a notification
-  Supports WebSockets, MQTT and Apple/Android push notification
   transports
-  Offers an authentication layer
-  Allows you to integrate custom hooks that can decide if an alarm
   needs to be sent out or not (an example of how this can be used for
   person detection is provided)

Is this officially developed by ZM developers?
----------------------------------------------

No. I developed it for zmNinja, but you can use it with your own
consumer.

How can I use this with Node-Red or Home Assistant?
---------------------------------------------------

As of version 1.1, the event server also supports MQTT (Contributed by
`@vajonam <https://github.com/vajonam>`__). zmeventnotification server can
be configured to broadcast on a topic called
``/zoneminder/<monitor-id>`` which can then be consumed by Home
Assistant or Node-Red.

To enable this, set ``enable = 1`` under the ``[mqtt]`` section and
specify the ``server`` to broadcast to.

You will also need to install the following module for this work

::

    perl -MCPAN -e "install Net::MQTT::Simple"

Disabling security
------------------

While I don't recommend either, several users seem to be interested in
the following

-  To run the eventserver on Websockets and not Secure Websockets, use
   ``enable = 0`` in the ``[ssl]`` section of the configuration file.
-  To disable ZM Auth checking (be careful, anyone can get all your data
   INCLUDING passwords for ZoneMinder monitors if you open it up to the
   Internet) use ``enable = 0`` in the ``[auth]`` section of the
   configuration file.

How do I safely upgrade zmeventnotification to new versions?
------------------------------------------------------------

::

    sudo zmdc.pl stop zmeventnotification.pl

Now copy the new zmeventnotification.pl to the right place (usually
``/usr/bin``) If you need to, copy the new zmeventnotification.ini to
the right place (usually ``/etc/zm``) (Note: this will replace your old
config file and you shouldn't need to do this)

::

    sudo zmdc.pl start zmeventnotification.pl

Make sure you look at the syslogs to make sure its started properly

Configuring the notification server
-----------------------------------

Understanding zmeventnotification configuration
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Starting v1.0, [@synthead](https://github.com/synthead) reworked the
configuration as follows:

-  If you just run ``zmeventnotification.pl`` it will try and load
   ``/etc/zm/zmeventnotification.ini``. If it doesn't find it, it will
   use internal defaults
-  If you want to override this with another configuration file, use
   ``zmeventnotification.pl --config /path/to/your/config/filename.ini``.
-  Its always a good idea to validate you config settings. For example:

::

    sudo /usr/bin/zmeventnotification.pl --check-config

    03/31/2018 16:52:23.231955 zmeventnotification[29790].INF [using config file: /etc/zm/zmeventnotification.ini]
    Configuration (read /etc/zm/zmeventnotification.ini):

    Port .......................... 9000
    Address ....................... XX.XX.XX.XX
    Event check interval .......... 5
    Monitor reload interval ....... 300

    Auth enabled .................. true
    Auth timeout .................. 20

    Use FCM ....................... true
    FCM API key ................... (defined)
    Token file .................... /var/lib/zmeventnotification/push/tokens.txt

    SSL enabled ................... true
    SSL cert file ................. /etc/zm/apache2/ssl/zoneminder.crt
    SSL key file .................. /etc/zm/apache2/ssl/zoneminder.key

    Verbose ....................... false
    Read alarm cause .............. true
    Tag alarm event id ............ false
    Use custom notification sound . false

    Hook .......................... '/usr/bin/person_detect_wrapper.sh'
    Use Hook Description........... true

What is the hook section ?
~~~~~~~~~~~~~~~~~~~~~~~~~~

The ``hook`` section allows you to invoke a custom script when an alarm
is triggered by ZM.

``hook_script`` points to the script that is invoked when an alarm
occurs

If the script returns success (exit value of 0) then the notification
server will send out an alarm notification. If not, it will not send a
notification to its listeners. This is useful to implement any custom
logic you may want to perform that decides whether this event is worth
sending a notification for.

Related to ``hook`` we also have a ``hook_description`` attribute. When
set to 1, the text returned by the hook script will overwrite the alarm
text that is notified.

We also have a ``skip_monitors`` attribute. This is a comma separated
list of monitors. When alarms occur in those monitors, hooks will not be
called and the ES will directly send out notifications (if enabled in
ES). This is useful when you don't want to invoke hooks for certain
monitors as they may be expensive (especially if you are doing object
detection)

Finally, ``keep_frame_match_type`` is really used when you enable
"bestmatch". It prefixes an ``[a]`` or ``[s]`` to tell you if object
detection succeeded in the alarmed or snapshot frame.

Here is an example: (Note: just an example, please don't ask me for
support for person detection)

-  You will find a sample ``detect_wrapper.sh`` hook in the ``hook``
   directory. This script is invoked by the notification server when an
   event occurs.
-  This script in turn invokes a python OpenCV based script that grabs
   an image with maximum score from the current event so far and runs a
   fast person detection routine.
-  It returns the value "person detected" if a person is found and none
   if not
-  The wrapper script then checks for this value and exits with either 0
   (send alarm) or 1 (don't send alarm)
-  the notification server then sends out a ": person detected"
   notification to the clients listening

Those who want to know more: - Read the detailed notes
`here <https://github.com/pliablepixels/zmeventnotification/tree/master/hook>`__
- Read
`this <https://medium.com/zmninja/inside-the-hood-machine-learning-enhanced-real-time-alarms-with-zoneminder-e26c34fe354c>`__
for an explanation of how this works

Troubleshooting common situations
---------------------------------

Picture notifications don't show images
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Starting v2.0, I support images in alarms. However, there are several
conditions to be met: \* You can't use self signed certs \* The
IP/hostname needs to be publicly accessible (Apple/Google servers render
the image) \* You need patches to ZM unless you are using a package that
is later than Oct 11, 2018. Please read the notes in the INI file \* A
good way to isolate if its a URL problem or something else is replace
the ``picture_url`` with a knows HTTPS url like
`this <https://upload.wikimedia.org/wikipedia/commons/5/5f/Chinese_new_year_dragon_2014.jpg>`__

Before you report issues, please make sure you have been diligent in
testing - Try with a public URL as indicated above. This is important. -
In your issue, post debug logs of zmeventnotification so I can see what
message it is sending

Secure mode just doesn't work (WSS) - WS works
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Try to put in your event server IP in the ``address`` token in
``[network]`` section of ``zmeventnotification.ini``

I'm not receiving push notifications in zmNinja
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This almost always happens when zmNinja is not able to reach the server.
Before you contact me, please perform the following steps and send me
the output:

1. Stop the event server. ``sudo zmdc.pl stop zmeventnotification.pl``
2. Do a ``ps -aef | grep zmevent`` and make sure no stale processes are
   running
3. Edit your ``/etc/zm/zmeventnotification.ini`` and make sure
   ``verbose = 1`` to get verbose logs
4. Run the server manually by doing
   ``sudo -u www-data /usr/bin/zmeventnotification.pl`` (replace with
   ``www-data`` with ``apache`` depending on your OS)
5. You should now see logs on the commandline like so that shows the
   server is running:

::

    018-12-20,08:31:32 About to start listening to socket
    12/20/2018 08:31:32.606198 zmeventnotification[12460].INF [main:582] [About to start listening to socket]
    2018-12-20,08:31:32 Secure WS(WSS) is enabled...
    12/20/2018 08:31:32.656834 zmeventnotification[12460].INF [main:582] [Secure WS(WSS) is enabled...]
    2018-12-20,08:31:32 Web Socket Event Server listening on port 9000
    12/20/2018 08:31:32.696406 zmeventnotification[12460].INF [main:582] [Web Socket Event Server listening on port 9000]

6. Now start zmNinja. You should see event server logs like this:

::

    2018-12-20,08:32:43 Raw incoming message: {"event":"push","data":{"type":"token","platform":"ios","token":"cVuLzCBsEn4:APA91bHYuO3hVJqTIMsm0IRNQEYAUa<deleted>GYBwNdwRfKyZV0","monlist":"1,2,4,5,6,7,11","intlist":"45,60,0,0,0,45,45","state":"enabled"}}

If you don't see these logs on the event server, zmNinja is not able to
connect to the event server. This may be because of several reasons: a)
Your event server IP/DNS is not reachable from your phone b) If you are
using SSL, your certificates are invalid (try disabling SSL first - both
on the event server and on zmNinja) c) Your zmNinja configuration is
wrong (the most common error I see is the server has SSL disabled, but
zmNinja is configured to use ``wss://`` instead of ``ws://``)

7. Assuming the above worked, go to zmNinja logs in the app. Somewhere
   in the logs, you should see a line similar to:

::

    Dec 20, 2018 05:50:41 AM DEBUG Real-time event: {"type":"","version":"2.4","status":"Success","reason":"","event":"auth"}

This indicates that the event server successfully authenticated the app.
If you see step 6 work but not step 7, you might have provided incorrect
credentials (and in that case, you'll see an error message)

8.  Finally, after all of the above succeeds, do a
    ``cat /var/lib/zmeventnotification/push/tokens.txt`` to make sure
    the device token that zmNinja sent is stored (desktop apps don't
    have a device token). If you are using zmNinja on a mobile app, and
    you don't see an entry in ``tokens.txt`` you have a problem. Debug.

9.  *Always* send me logs of both zmNinja and zmeventnotification - I
    need them to understand what is going on. Don't send me one line.
    You may think you are sending what is relevant, but you are not. One
    line logs are mostly useless.

10. Some other notes:

-  If you don't see an entry in ``tokens.txt`` (typically in
   ``/var/lib/zmeventnotification/push``) then your phone is not
   registered to get push. Kill zmNinja, start the app, make sure the
   event server receives the registration and check ``tokens.txt``

-  Sometimes, Google's FCM server goes down, or Apple's APNS server goes
   down for a while. Things automagically work in 24 hrs.

-  Kill the app. Then empty the contents of ``tokens.txt`` in the event
   server (don't delete it). Then restart the event server. Start the
   app again. If you don't see a new registration token, you have a
   connection problem

-  I'd strongly recommend you run the event server in "manual mode" and
   stop daemon mode while debugging.

I'm getting multiple notifications for the same event
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

99.9% of times, its because you have multiple copies of the eventserver
running and you don't know it. Maybe you were manually testing it, and
forgot to quit it and terminated the window. Do
``sudo zmdc.pl stop zmeventnotification.pl`` and then
``ps -aef | grep zme``, kill everything, and start again. Monitor the
logs to see how many times a message is sent out.

The other 0.1% is at times Google's FCM servers send out multiple
notifications. Why? I don't know. But it sorts itself out very quickly,
and if you think this must be the reason, I'll wager that you are
actually in the 99.9% lot and haven't checked properly.

The server runs fine when manually executed, but fails when run in daemon mode (started by zmdc.pl)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

-  Make sure the file where you store tokens
   (``/var/lib/zmeventnotification/push/tokens.txt or whatever you have used``)
   is not RW Root only. It needs to be RW ``www-data`` for Ubuntu/Debian
   or ``apache`` for Fedora/CentOS. You also need to make sure the
   directory is accessible. Something like
   ``chown -R www-data:www-data /var/lib/zmeventnotification/push``

-  Make sure your certificates are readable by ``www-data`` for
   Ubuntu/Debian, or ``apache`` for Fedora/CentOS (thanks to
   [@jagee](https://github.com/pliablepixels/zmeventnotification/issues/8))
-  Make sure the *path* to the certificates are readable by ``www-data``
   for Ubuntu/Debian, or ``apache`` for Fedora/CentOS

When you run zmeventnotifiation.pl manually, you get an error saying 'port already in use' or 'cannot bind to port' or something like that
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The chances are very high that you have another copy of
``zmeventnotification.pl`` running. You might have run it in daemon
mode. Try ``sudo zmdc.pl stop zmeventnotification.pl``. Also do
``ps -aef | grep zmeventnotification`` to check if another copy is not
running and if you do find one running, you'll have to kill it before
you can start it from command line again.

Great Krypton! I just upgraded ZoneMinder and I'm not getting push anymore!
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Make sure your eventserver is running:
``sudo zmdc.pl status zmeventnotification.pl``

How do I disable secure (WSS) mode?
-----------------------------------

As it turns out many folks run ZM inside the LAN only and don't want to
deal with certificates. Fair enough. For that situation, edit
zmeventnotification.pl and use ``enable = 0`` in the ``[ssl]`` section
of the configuration file. **Remember to ensure that your EventServer
URL in zmNinja does NOT use wss too - change it to ws**

.. _debug_reporting_es:

Debugging and reporting problems
--------------------------------

STOP. Before you shoot me an email, **please** make sure you have read
the `common problems <#troubleshooting-common-situations>`__ and have
followed *every step* of the `install guide <#how-do-i-install-it>`__
and in sequence. I can't emphasize how important it is.

There could be several reasons why you may not be receiving
notifications:

-  Your event server is not running
-  Your app is not able to reach the server
-  You have enabled SSL but the certificate is invalid
-  The event server is rejecting the connections

Here is how to debug and report:

-  Enable Debug logs in zmNinja (Setting->Developer Options->Enable
   Debug Log)
-  telnet/ssh into your zoneminder server
-  Stop the zmeventnotification doing
   ``sudo zmdc.pl stop zmeventnotification.pl``
-  Make sure there are no stale processes running of zmeventnotification
   by doing ``ps -aef | grep zmeventnotification`` and making sure it
   doesn't show existing processes (ignore the one that says
   ``grep <something>``)
-  Edit ``zmeventnotification.ini`` (typically in ``/etc/zm/``) and make
   sure ``verbose = 1`` is set. This will print more logs on the
   console. Make sure you turn this off again before switching back to
   daemon mode.
-  Start a terminal (lets call it Terminal-Log) to tail logs like so
   ``tail -f /var/log/syslog | grep zmeventnotification``
-  Start another terminal and start zmeventnotification manually from
   command line like so ``sudo /usr/bin/zmeventnotification.pl``
-  Make sure you see logs like this in the logs window like so:

::

    Nov 26 14:27:20 homeserver zmdc[18560]: INF ['zmeventnotification.pl' started at 17/11/26 14:27:20]
    Nov 26 14:27:20 homeserver zmeventnotification[18560]: INF [Push enabled via FCM]
    Nov 26 14:27:20 homeserver zmeventnotification[18560]: INF [Event Notification daemon v 0.95 starting]
    Nov 26 14:27:20 homeserver zmeventnotification[18560]: INF [Total event client connections: 3]
    Nov 26 14:27:20 homeserver zmeventnotification[18560]: INF [Reloading Monitors...]
    Nov 26 14:27:21 homeserver zmeventnotification[18560]: INF [Loading monitors]
    Nov 26 14:27:21 homeserver zmeventnotification[18560]: INF [About to start listening to socket]
    Nov 26 14:27:21 homeserver zmeventnotification[18560]: INF [Secure WS(WSS) is enabled...]
    Nov 26 14:27:21 homeserver zmeventnotification[18560]: INF [Web Socket Event Server listening on port 9000]

-  Open up zmNinja, clear logs
-  Enable event server in zmNinja
-  Check that when you save the event server connections in zmNinja, you
   see logs in the log window like this

::

    Oct 20 10:23:18 homeserver zmeventnotification[27789]: INF [got a websocket connection from XX.XX.XX.XX (11) active connections]
    Oct 20 10:23:18 homeserver zmeventnotification[27789]: INF [Websockets: New Connection Handshake requested from XX.XX.XX.XX:55189 state=pending auth]
    Oct 20 10:23:18 homeserver zmeventnotification[27789]: INF [Correct authentication provided byXX.XX.XX.XX]
    Oct 20 10:23:18 homeserver zmeventnotification[27789]: INF [Storing token ...9f665f182b,monlist:-1,intlist:-1,pushstate:enabled]
    Oct 20 10:23:19 homeserver zmeventnotification[27789]: INF [Contrl: Storing token ...9f665f182b,monlist:1,2,4,5,6,7,10,intlist:0,0,0,0,0,0,0,pushstate:enabled]

If you don't see anything there is a connection problem. Review SSL
guidelines above, or temporarily turn off websocket SSL as described
above

-  Open up ZM console and force an alarm, you should see logs in your
   log window above like so:

::

    Oct 20 10:28:55 homeserver zmeventnotification[27789]: INF [New event 32910 reported for Garage]
    Oct 20 10:28:55 homeserver zmeventnotification[27789]: INF [Broadcasting new events to all 12 websocket clients]
    Oct 20 10:28:55 homeserver zmeventnotification[27789]: INF [Checking alarm rules for  token ending in:...2baa57e387]
    Oct 20 10:28:55 homeserver zmeventnotification[27789]: INF [Monitor 1 event: last time not found, so sending]
    Oct 20 10:28:55 homeserver zmeventnotification[27789]: INF [Sending notification over PushProxy]
    Oct 20 10:28:56 homeserver zmeventnotification[27789]: INF [Pushproxy push message success ]

-  If you are debugging problems with receiving push notifications on
   zmNinja mobile, then replicate the following scenario:

-  Run the event server in manual mode as described above
-  Kill zmNinja
-  Start zmNinja
-  At this point, in the ``zmeventnotification`` logs you should
   registration messages (refer to logs example above). If you don't
   you've either not configured zmNinja to use the eventserver, or it
   can't reach the eventserver (very common problem)
-  Next up, make sure you are not running zmNinja in the foreground
   (move it to background or kill it). When zmNinja is in the
   foreground, it uses websockets to get notifications
-  Force an alarm like I described above. If you don't see logs in
   ``zmeventnotification`` saying "Sending notification over PushProxy"
   then the eventserver, for some reason, does not have your app token.
   Inspeced ``tokens.txt`` (typically in ``/etc/zm/``) to make sure an
   entry for your phone exists
-  If you see that message, but your mobile phone is not receiving a
   push notification:
-  Make sure you haven't disable push notifications on your phone (lots
   of people do this by mistake and wonder why)
-  Make sure you haven't muted notifications (again, lots of people...)
-  Sometimes, the push servers of Apple and Google stop forwarding
   messages for a day or two. I have no idea why. Give it a day or two?
-  Open up zmNinja, go right to logs and send it to me

-  If you have issues, please send me a copy of your zmeventnotification
   logs generated above from Terminal-Log, as well as zmNinja debug logs

How scalable is it?
-------------------

It's a lightweight single threaded process. I really don't see a need
for launching a zillion threads or a process per monitor etc for what it
does. I'd argue its simplicity is its scalability. Plus I don't expect
more than a handful of consumers to connect to it. I really don't see
why it won't be able to scale to for what is does. But if you are facing
scalability issues, let me know. There is
`Mojolicious <http://mojolicio.us/>`__ I can use to make it more
scalable if I am proven wrong about scalability.

Brickbats
---------

**Why not just supply the username and password in the URL as a
resource? It's over TLS**

Yup its encrypted but it may show up in the history of a browser you
tried it from (if you are using a browser) Plus it may get passed along
from the source when accessing another URL via the Referral header

**So it's encrypted, but passing password is a bad idea. Why not some
token?**

-  Too much work.
-  Plus I'm an unskilled programmer. Pull Requests welcome

**Why WSS and not WS?**

Not secure. Easy to snoop. Updated: As of 0.6, I've also added a non
secure version - use ``enable = 0`` in the ``[ssl]`` section of the
configuration file. As it turns out many folks don't expose ZM to the
WAN and for that, I guess WS instead of WSS is ok.

**Why ZM auth in addition to WSS?**

WSS offers encryption. We also want to make sure connections are
authorized. Reusing ZM authentication credentials is the easiest. You
can change it to some other credential match (modify ``validateZM``
function)
