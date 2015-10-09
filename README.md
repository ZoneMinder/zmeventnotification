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

* Edit ``/usr/bin/zmdc.pl`` and in the array ``@daemons`` (starting line 80) add ``'zmeventnotification.pl'`` like [this](https://gist.github.com/pliablepixels/18bb68438410d5e4b644)
* Edit /usr/bin/zmpkg.pl and around line 260, right after the comment that says ``#this is now started unconditionally`` and right before the line that says ``runCommand( "zmdc.pl start zmfilter.pl" );`` start zmeventnotification.pl by adding ``runCommand( "zmdc.pl start zmeventnotification.pl" );`` like  [this](https://gist.github.com/pliablepixels/0977a77fa100842e25f2)

You can/should run it manually at first to check if it works 

###Dependencies
The following perl packages need to be added
 
* Crypt::MySQL
* Net::WebSocket::Server

Installing these dependencies is as simple as:
```
perl -MCPAN -e "install Crypt::MySQL"
perl -MCPAN -e "install Net::WebSocket::Server"
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
* By default the notification server runs on port 9000 (unless you change it)
* You need to open a secure web socket connection to that port from your client/consumer
* You then need to provide your authentication credentials (ZoneMinder username/password) within 20 seconds of opening the connection
* If you provide an incorrect authentication or no authentication, the server will close your connection

###Messaging format

``{"JSON":"everywhere"}``
 
* Your client sends messages (authentication) over JSON
* The server sends auth success/failure over JSON back at you
* New events are reported as JSON objects as well

To connect with the server you need to send the following JSON object (replace username/password)
Note this is encrypted
```
{user:username,
 password:password}
```
The server will send back the following responses 

Authentication successful:
```
{"status":"Success","reason":""}
```

Incorrect credentials:
```
{"status":"Fail","reason":"BADAUTH"}
```

No authentication received in time limit:
```
{"status":"Fail","reason":"NOAUTH"}
```
Sample payload of 2 events being reported:
```
{"events":[{"EventId":"5060","Name":"Garage","MonitorId":"1"},{"EventId":"5061","MonitorId":"5","Name":"Unfinished"}],"status":"Success"}
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

