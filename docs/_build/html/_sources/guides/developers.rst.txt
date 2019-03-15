For Developers writing their own consumers
------------------------------------------

How do I talk to it?
~~~~~~~~~~~~~~~~~~~~

-  ``{"JSON":"everywhere"}``
-  Your client sends messages (authentication) over JSON
-  The server sends auth success/failure over JSON back at you
-  New events are reported as JSON objects as well
-  By default the notification server runs on port 9000 (unless you
   change it)
-  You need to open a secure web socket connection to that port from
   your client/consumer
-  You then need to provide your authentication credentials (ZoneMinder
   username/password) within 20 seconds of opening the connection
-  If you provide an incorrect authentication or no authentication, the
   server will close your connection
-  As of today, there are 3 categories of message types your client
   (zmNinja or your own) can exchange with the server (event
   notification server)

1. auth (from client to server)
2. control (from client to server)
3. push (only applicable for zmNinja)
4. alarm (from server to client)

Authentication messages
^^^^^^^^^^^^^^^^^^^^^^^

To connect with the server you need to send the following JSON object
(replace username/password) Note this payload is NOT encrypted. If you
are not using SSL, it will be sent in clear.

Authentication messages can be sent multiple times. It is necessary that
you send the first one within 20 seconds of opening a connection or the
server will terminate your connection.

**Client --> Server:**

::

    {"event":"auth","data":{"user":"<username>","password":"<password>"}}

**Server --> Client:** The server will send back one of the following
responses

Authentication successful:

::

    {"event":"auth", "type":"", "version":"0.2","status":"Success","reason":""}

Note that it also sends its version number for convenience

Incorrect credentials:

::

    {"event":"auth", "type":"", "status":"Fail","reason":"BADAUTH"}

No authentication received in time limit:

::

    {"event":"auth","type":"", "status":"Fail","reason":"NOAUTH"}

Control messages
^^^^^^^^^^^^^^^^

Control messages manage the nature of notifications received/sent. As of
today, Clients send control messages to the Server. In future this may
be bi-directional

Control message to restrict monitor IDs for events as well as interval durations for reporting
''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

A client can send a control message to restrict which monitor IDs it is
interested in. When received, the server will only send it alarms for
those specific monitor IDs. You can also specify the reporting interval
for events.

**Client-->Server:**

::

    {"event":"control","data":{"type":"filter","monlist":"1,2,4,5,6", "intlist":"0,0,3600,60,0"}}

In this example, a client has requested to be notified of events only
from monitor IDs 1,2,4,5 and 6 Furthermore it wants to be notified for
each alarm for monitors 1,2,6. For monitor 4, it wants to be notified
only if the time difference between the previous and current event is 1
hour or more (3600 seconds) while for monitor 5, it wants the time
difference between the previous and current event to be 1 minute (60
seconds)

There is no response for this request, unless the payload did not have
either monlist or intlist.

No monitorlist received:

::

    {"event":"control","type":"filter", "status":"Fail","reason":"NOMONITORLIST"}

No interval received:

::

    {"event":"control","type":"filter", "status":"Fail","reason":"NOINTERVALLIST"}

Note that if you don't want to specify intervals, send it a interval
list comprising of comma separated 0's, one for each monitor in monitor
list.

Control message to get Event Server version
'''''''''''''''''''''''''''''''''''''''''''

A client can send a control message to request Event Server version

**Client-->Server:**

::

    {"event":"control","data":{"type":"version"}}

**Server-->Client:**

::

    {"event":"control", "type:":"version", "version":"0.2","status":"Success","reason":""}

Alarm notifications
^^^^^^^^^^^^^^^^^^^

Alarms are events sent from the Server to the Client

**Server-->Client:** Sample payload of 2 events being reported:

::

    {"event":"alarm", "type":"", "status":"Success", "events":[{"EventId":"5060","Name":"Garage","MonitorId":"1"},{"EventId":"5061","MonitorId":"5","Name":"Unfinished"}]}

Push Notifications (for both iOS and Android)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

To make Push Notifications work, please make sure you read the `section
on enabling
Push <https://github.com/pliablepixels/zmeventnotification#44-apnsgcm-howto---only-applicable-for-zmninja-not-for-other-consumers>`__
for the event server.

Concepts of Push and why it is only for zmNinja
'''''''''''''''''''''''''''''''''''''''''''''''

Both Apple and Google ensure that a "trusted" application server can
send push notifications to a specific app running in a device. If they
did not require this, anyone could spam apps with messages. So in other
words, a "Push" will be routed from a specific server to a specific app.
Starting Jan 2018, I am hosting my trusted push server on Google's
Firebase cloud. This eliminates the need for me to run my own server.

Registering Push token with the server
''''''''''''''''''''''''''''''''''''''

**Client-->Server:**

Registering an iOS device:

::

    {"event":"push","data":{"type":"token","platform":"ios","token":"<device tokenid here>", "state":"enabled"}}

Here is an example of registering an Android device:

::

    {"event":"push","data":{"type":"token","platform":"android","token":"<device tokenid here>", "state":"enabled"}}

For devices capable of receiving push notifications, but want to stop
receiving push notifications over APNS/GCM and have it delivered over
websockets instead, set the state to disabled

For example: Here is an example of registering an Android device, which
disables push notifications over GCM:

::

    {"event":"push","data":{"type":"token","platform":"android","token":"<device tokenid here>", "state":"disabled"}}

What happens here is if there is a new event to report, the Event Server
will send it over websockets. This means if the app is running
(foreground or background in Android, foreground in iOS) it will receive
this notification over the open websocket. Note that in iOS this means
you won't receive notifications when the app is not running in the
foreground. We went over why, remember?

**Server-->Client:** If its successful, there is no response. However,
if Push is disabled it will send back

::

    {"event":"push", "type":"", "status":"Fail", "reason": "PUSHDISABLED"}

Badge reset
'''''''''''

Only applies to iOS. Android push notifications don't have a concept of
badge notifications, as it turns out.

In push notifications, the server owns the responsibility for badge
count (unlike local notifications). So a client can request the server
to reset its badge count so the next push notification starts from the
value provided.

**Client-->Server:**

::

    {"event":"push", "data":{"type":"badge", "badge":"0"}}

In this example, the client requests the server to reset the badge count
to 0. Note that you can use any other number. The next time the server
sends a push via APNS, it will use this value. 0 makes the badge go
away.

Testing from command line
^^^^^^^^^^^^^^^^^^^^^^^^^

If you are writing your own consumer/client it helps to test the event
server commands from command line. The event server uses
Secure/WebSockers so you can't just HTTP to it using tools like
``curl``. You'll need to use a websocket client. While there are
examples on the net on how to use ``curl`` for websockets, I've found it
much simpler to use `wscat <https://github.com/websockets/wscat>`__ like
so:

::

    wscat -c wss://myzmeventnotification.domain:9000 -n
    connected (press CTRL+C to quit)
    > {"event":"auth","data":{"user":"admin","password":"xxxx"}}
    < {"reason":"","status":"Success","type":"","event":"auth","version":"0.93"}

In the example above, I used ``wscat`` to connect to my event server and
then sent it a JSON login message which it accepted and acknowledged.
