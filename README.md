### What is it?
A WSS (Secure Web Sockets) based event notification server that broadcasts new events to any authenticated listeners.

### What can you do with it?
Well, [zmNinja](https://github.com/pliablepixels/zmNinja) uses it to display real time notifications of events.
Watch a video [HERE](https://www.youtube.com/watch?v=HhLKrDrj7rs)
You can implement your own receiver to get real time event notification and do whatever your hear desires 

### Why do we need it?
* The only way ZoneMinder sends out event notifications via event filters - this is too slow
* People developing extensions to work with ZoneMinder for Home Automation needs will benefit from a clean interface
* Receivers don't poll. They keep a web socket open and when there are events, they get a notification

###Is this officially developed by ZM developers?
No. I developed it for zmNinja, but you can use it with your own consumer.

### Where can I get it?
* Grab the script from this repository - its a perl file.
* Place it along with other ZM scripts (see below)

###How do I install it?

* Grab the server (its a simple perl file) and place it in the same place other ZM scripts are stored (example ``/usr/bin``)
* Either run it manually like ``sudo /usr/bin/zmeventnotification.pl`` or add it as a daemon to ``/usr/bin/zmdc.pl`` (the advantage of the latter is that it gets automatically started when ZM starts
and restarted if it crashes)

#####How do I run it as a daemon so it starts automatically along with ZoneMinder?

**WARNING: Do NOT do this before you run it manually as I've mentioned above to test. Make sure it works, all packages are present etc. before you 
add it as  a daemon as if you don't and it crashes you won't know why**

(Note if you have compiled from source using cmake, the paths may be ``/usr/local/bin`` not ``/usr/bin``)

* Copy ``zmeventnotification.pl`` to ``/usr/bin``
* Edit ``/usr/bin/zmdc.pl`` and in the array ``@daemons`` (starting line 80) add ``'zmeventnotification.pl'`` like [this](https://gist.github.com/pliablepixels/18bb68438410d5e4b644)
* Edit ``/usr/bin/zmpkg.pl`` and around line 260, right after the comment that says ``#this is now started unconditionally`` and right before the line that says ``runCommand( "zmdc.pl start zmfilter.pl" );`` start zmeventnotification.pl by adding ``runCommand( "zmdc.pl start zmeventnotification.pl" );`` like  [this](https://gist.github.com/pliablepixels/0977a77fa100842e25f2)
* Make sure you restart ZM. Rebooting the server is better - sometimes zmdc hangs around and you'll be wondering why your new daemon hasn't started
* To check if its running do a ``zmdc.pl status zmeventnotification.pl``

You can/should run it manually at first to check if it works 

###Dependencies
The following perl packages need to be added
 
* Crypt::MySQL
* Net::WebSocket::Server

Installing these dependencies is as simple as:
```
perl -MCPAN -e "install Crypt::MySQL"
```

If you face issues installing Crypt::MySQL try this instead: (Thanks to aaronl)
```
sudo apt-get install libcrypt-mysql-perl
```

Next up install WebSockets
```
sudo apt-get install libyaml-perl
sudo apt-get install make
perl -MCPAN -e "install Net::WebSocket::Server"
```

Finally, you need JSON.pm installed. It's there on some systems and not on others
In ubuntu, do this to install JSON:
```
apt-get install libjson-perl
```

You **also need to make sure you generate SSL certificates otherwise the script won't run**
If you are using SSL for ZoneMinder, simply point this script to the certificates.
If you are not, please generate them. You can read up how to do that [here](https://github.com/pliablepixels/zmNinja/blob/master/docs/SSL-Configuration.md)

Once you do that please change the following lines in the perl server to point to your SSL certs/keys:
```
use constant SSL_CERT_FILE=>'/etc/apache2/ssl/zoneminder.crt';	 
use constant SSL_KEY_FILE=>'/etc/apache2/ssl/zoneminder.key';
```
###How do I talk to it?
*  ``{"JSON":"everywhere"}``
* Your client sends messages (authentication) over JSON
* The server sends auth success/failure over JSON back at you
* New events are reported as JSON objects as well
* By default the notification server runs on port 9000 (unless you change it)
* You need to open a secure web socket connection to that port from your client/consumer
* You then need to provide your authentication credentials (ZoneMinder username/password) within 20 seconds of opening the connection
* If you provide an incorrect authentication or no authentication, the server will close your connection
* As of today, there are 3 categories of message types your client (zmNinja or your own) can exchange with the server (event notification server)
 1. auth (from client to server)
 1. control (from client to server)
 1. push (from client to server, used for APNS iOS notifications as of now)
 1. alarm (from server to client)


#### Authentication messages

To connect with the server you need to send the following JSON object (replace username/password)
Note this is encrypted

Authentication messages can be sent multiple times. It is necessary that you send the first one
within 20 seconds of opening a connection or the server will terminate your connection.

**Client --> Server:**
```
{"event":"auth","data":{"user":"<username>","password":"<password>"}}
```

**Server --> Client:**
The server will send back the following responses 

Authentication successful:
```
{"version":"0.2","status":"Success","reason":""}
```
Note that it also sends its version number for convenience

Incorrect credentials:
```
{"status":"Fail","reason":"BADAUTH"}
```

No authentication received in time limit:
```
{"status":"Fail","reason":"NOAUTH"}
```

#### Control messages
Control messages manage the nature of notifications received/sent. As of today, Clients send control messages to the Server.
In future this may be bi-directional

#####Control message to restrict monitor IDs for events
A client can send a control message to restrict which monitor IDs it is interested in. When received, the server will only
send it alarms for those specific monitor IDs

**Client-->Server:**
```
{"event":"control","data":{"type":"filter","monlist":"1,2,4,5,6"}}
```
In this example, a client has requested to be notified of events only from monitor IDs 1,2,4,5 and 6

There is no response for this request.


#####Control message to get Event Server version
A client can send a control message to request Event Server version

**Client-->Server:**
```
{"event":"control","data":{"type":"version"}}
```

**Server-->Client:**
```
{"version":"0.2","status":"Success","reason":""}
```

###Alarm notifications
Alarms are events sent from the Server to the Client

Sample payload of 2 events being reported:
```
{"event":"alarm", "status":"Success", "events":[{"EventId":"5060","Name":"Garage","MonitorId":"1"},{"EventId":"5061","MonitorId":"5","Name":"Unfinished"}]}
```

###How scalable is it?
It's a lightweight single threaded process. I really don't see a need for launching a zillion threads or a process per monitor etc for what it does. I'd argue its simplicity is its scalability. Plus I don't expect more than a handful of consumers to connect to it. I really don't see why it won't be able to scale to for what is does. But if you are facing scalability issues, let me know. There is [Mojolicious](http://mojolicio.us/) I can use to make it more scalable if I am proven wrong about scalability.

###Brickbats

**Why not just supply the username and password in the URL as a resource? It's over TLS**

Yup its encrypted but it may show up in the history of a browser you tried it from (if you are using a browser)
Plus it may get passed along from the source when accessing another URL via the Referral header

**So it's encrypted, but passing password is a bad idea. Why not some token?**
* Too much work. 
* Plus I'm an unskilled programmer. Pull Requests welcome

**Why WSS and not WS?**

Not secure. Easy to snoop.

**Why ZM auth in addition to WSS?**

WSS offers encryption. We also want to make sure connections are authorized. Reusing ZM authentication credentials is the easiest. You can change it to some other credential match (modify ``validateZM`` function)

