**Latest Version: 2.6**

<!-- TOC -->

- [Breaking Changes](#breaking-changes)
    - [version 1.0 onwards](#version-10-onwards)
- [Machine Learning! Mmm..Machine Learning!](#machine-learning-mmmmachine-learning)
- [What is it?](#what-is-it)
- [Why do we need it?](#why-do-we-need-it)
- [Is this officially developed by ZM developers?](#is-this-officially-developed-by-zm-developers)
- [How do I install it?](#how-do-i-install-it)
    - [Download the server script and its config file](#download-the-server-script-and-its-config-file)
    - [Install Dependencies](#install-dependencies)
    - [SSL certificate (Generate new, or use ZoneMinder certs if you are already using HTTPS)](#ssl-certificate-generate-new-or-use-zoneminder-certs-if-you-are-already-using-https)
        - [IOS Users](#ios-users)
    - [Making sure everything is running (in manual mode)](#making-sure-everything-is-running-in-manual-mode)
    - [Running it as a daemon so it starts automatically along with ZoneMinder](#running-it-as-a-daemon-so-it-starts-automatically-along-with-zoneminder)
- [How can I use this with Node-Red or Home Assistant?](#how-can-i-use-this-with-node-red-or-home-assistant)
- [Disabling security](#disabling-security)
- [How do I safely upgrade zmeventserver to new versions?](#how-do-i-safely-upgrade-zmeventserver-to-new-versions)
- [Configuring the notification server](#configuring-the-notification-server)
    - [Understanding zmeventnotification configuration](#understanding-zmeventnotification-configuration)
    - [What is the hook attribute ?](#what-is-the-hook-attribute-)
- [Troubleshooting common situations](#troubleshooting-common-situations)
    - [Picture notifications don't show images](#picture-notifications-dont-show-images)
    - [Secure mode just doesn't work (WSS) - WS works](#secure-mode-just-doesnt-work-wss---ws-works)
    - [I'm not receiving push notifications in zmNinja](#im-not-receiving-push-notifications-in-zmninja)
    - [I'm getting multiple notifications for the same event](#im-getting-multiple-notifications-for-the-same-event)
    - [The server runs fine when manually executed, but fails when run in daemon mode (started by zmdc.pl)](#the-server-runs-fine-when-manually-executed-but-fails-when-run-in-daemon-mode-started-by-zmdcpl)
    - [When you run zmeventnotifiation.pl manually, you get an error saying 'port already in use' or 'cannot bind to port' or something like that](#when-you-run-zmeventnotifiationpl-manually-you-get-an-error-saying-port-already-in-use-or-cannot-bind-to-port-or-something-like-that)
    - [Great Krypton! I just upgraded ZoneMinder and I'm not getting push anymore!](#great-krypton-i-just-upgraded-zoneminder-and-im-not-getting-push-anymore)
- [How do I disable secure (WSS) mode?](#how-do-i-disable-secure-wss-mode)
- [Debugging and reporting problems](#debugging-and-reporting-problems)
- [For Developers writing their own consumers](#for-developers-writing-their-own-consumers)
    - [How do I talk to it?](#how-do-i-talk-to-it)
        - [Authentication messages](#authentication-messages)
        - [Control messages](#control-messages)
            - [Control message to restrict monitor IDs for events as well as interval durations for reporting](#control-message-to-restrict-monitor-ids-for-events-as-well-as-interval-durations-for-reporting)
            - [Control message to get Event Server version](#control-message-to-get-event-server-version)
        - [Alarm notifications](#alarm-notifications)
        - [Push Notifications (for both iOS and Android)](#push-notifications-for-both-ios-and-android)
            - [Concepts of Push and why it is only for zmNinja](#concepts-of-push-and-why-it-is-only-for-zmninja)
            - [Registering Push token with the server](#registering-push-token-with-the-server)
            - [Badge reset](#badge-reset)
        - [Testing from command line](#testing-from-command-line)
- [How scalable is it?](#how-scalable-is-it)
- [Brickbats](#brickbats)

<!-- /TOC -->

## Breaking Changes
### version 1.0 onwards

Version 1.0 moves configuration to a separate `zmeventnotification.ini` file that makes it easier to re-configure. If you are already
a user of previous versions and want to migrate to 1.0, please make sure you copy `zmeventnotification.ini` to `/etc`. You will need
to re-configure the params to your liking in the ini file. Note that you may need to install some additional packages like `Config::IniFiles` if it complains of missing libraries.

If you are installing `zmeventnotification` for the first time, just read the [How do I install it?](#how-do-i-install-it) section.

## Machine Learning! Mmm..Machine Learning!

Easy. You will first have to read this document to correctly install this server along with zoneminder. Once it works well, you can explore how to enable Machine Learning based object detection that can be used along with ZoneMinder alarms. If you already have this server figured out, you can skip directly to the machine learning part [here](https://github.com/pliablepixels/zmeventserver/blob/master/hook_example/README.md)

## What is it?

A WSS (Secure Web Sockets) and/or MQTT based event notification server that broadcasts new events to any authenticated listeners.
(As of 0.6, it also includes a non secure websocket option, if that's how you want to run it)

## Why do we need it?
- The only way ZoneMinder sends out event notifications via event filters - this is too slow
- People developing extensions to work with ZoneMinder for Home Automation needs will benefit from a clean interface
- Receivers don't poll. They keep a web socket open and when there are events, they get a notification
- Supports WebSockets, MQTT and Apple/Android push notification transports
- Offers an authentication layer
- Allows you to integrate custom hooks that can decide if an alarm needs to be sent out or not (an example of how this can be used for person detection is provided)

## Is this officially developed by ZM developers?

No. I developed it for zmNinja, but you can use it with your own consumer.

## How do I install it?

### Download the server script and its config file

- Clone the project to some directory `git clone https://github.com/pliablepixels/zmeventserver.git`
- Edit `zmeventnotification.ini` to your liking. More details about various parts of the configuration are explained later in this readme
- If you are behind a firewall, make sure you enable port `9000`, TCP, bi-directional (unless you changed the port in the code)
- We now need to install a bunch of dependencies (as described below)

### Install Dependencies

Note that I assume you have other development packages already installed like `make`, `gcc` etc as the plugins may require them.
The following perl packages need to be added (these are for Ubuntu - if you are on a different OS, you'll have to figure out which packages are needed - I don't know what they might be)

(**General note** - some users may face issues installing dependencies via `perl -MCPAN -e "Module::Name"`. If so, its usually more reliable to get into the CPAN shell and install it from the shell as a 2 step process. You'd do that using `sudo perl -MCPAN -e shell` and then whilst inside the shell, `install Module::Name`)

- Crypt::MySQL
- Net::WebSocket::Server
- Config::IniFiles (you may already have this installed)

Installing these dependencies is as simple as:

```
perl -MCPAN -e "install Crypt::MySQL"
perl -MCPAN -e "install Config::IniFiles"
```

If after installing them you still see errors about these libraries missing, please launch a CPAN shell - see General Note above.

If you face issues installing Crypt::MySQL try this instead: (Thanks to aaronl)

```
sudo apt-get install libcrypt-mysql-perl
```
If there are issues installing Config::IniFiles and the errors are related to Module::Build missing, use following command to get this module in debian based systems and install Config::IniFiles again.
```
sudo apt-get install libmodule-build-perl
```
Next up install WebSockets

```
sudo apt-get install libyaml-perl
sudo apt-get install make
sudo perl -MCPAN -e "install Net::WebSocket::Server"
```

Then, you need JSON.pm installed. It's there on some systems and not on others
In ubuntu, do this to install JSON:

```
sudo apt-get install libjson-perl
```

Get HTTPS library for LWP:

```
perl -MCPAN -e "install LWP::Protocol::https"
```

If you want to enable MQTT:

```
perl -MCPAN -e "install Net::MQTT::Simple"
```

Note that starting 1.0, we also use `File::Spec`, `Getopt::Long` and `Config::IniFiles` as additional libraries. My ubuntu
installation seemed to include all of this by default (even though `Config::IniFiles` is not part of base perl).

If you get errors about missing libraries, you'll need to install the missing ones like so:

```
perl -MCPAN -e "install XXXX" # where XXX is Config::IniFiles, for example
```

### SSL certificate (Generate new, or use ZoneMinder certs if you are already using HTTPS)

If you are using secure mode (default) you **also need to make sure you generate SSL certificates otherwise the script won't run**
If you are using SSL for ZoneMinder, simply point this script to the certificates.

If you are not already using SSL for ZoneMinder and don't have certificates, generating them is as
easy as:

(replace /etc/apache2/ssl/ with the directory you want the certificate and key files to be stored in)

```
sudo openssl req -x509 -nodes -days 4096 -newkey rsa:2048 -keyout /etc/apache2/ssl/zoneminder.key -out /etc/apache2/ssl/zoneminder.crt
```

It's **very important** to ensure the `Common Name` selected while generating the certificate is the same as the hostname or IP of the server. For example if you plan to access the server as `myserver.ddns.net` Please make sure you use `myserver.ddns.net` as the common name. If you are planning to access it via IP, please make sure you use the same IP.

Once you do that please change the following options in the config file to point to your SSL certs/keys:

```
[ssl]
cert = /etc/apache2/ssl/zoneminder.crt
key = /etc/apache2/ssl/zoneminder.key
```

#### IOS Users

Starting IOS 10.2, I noticed that zmNinja was not able to register with the event server when it was using WSS (SSL enabled) and self-signed certificates. To solve this, I had to email myself the zoneminder certificate (`zoneminder.crt`) file and install it in the phone. Why that is needed only for WSS and not for HTTPS is a mystery to me. The alternative is to run the eventserver in WS mode by disabling SSL.

### Making sure everything is running (in manual mode)

- I am assuming you have downloaded the  files to your current directory in the step below
- Make sure you do a `chmod a+x ./zmeventnotification.pl`
- Start the event server manually first using `sudo -u www-data ./zmeventnotification.pl --config ./zmeventnotification.ini` (Note that if you omit `--config` it will look for `/etc/zmeventnotification.ini` and if that doesn't exist, it will use default values) and make sure you check syslogs to ensure its loaded up and all dependencies are found. If you see errors, fix them. Then exit and follow the steps below to start it along with Zoneminder. Note that the `-u www-data` runs this command with the user id that apache uses (in some systems this may be `apache` or similar). It is important to run it using the same user id as your webserver because that is the permission zoneminder will use when run as a daemon mode.

- Its is HIGHLY RECOMMENDED that you first start the event server manually from terminal, as described above and not directly dive into daemon mode (described below) and ensure you inspect syslog to validate all logs are correct and THEN make it a daemon in ZoneMinder. If you don't, it will be hard to know what is going wrong. See the [debugging](https://github.com/pliablepixels/zmeventserver#debugging-and-reporting-problems) section later that describes how to make sure its all working fine from command line.

### Running it as a daemon so it starts automatically along with ZoneMinder

- Move `zmeventnotification.pl` to `/usr/bin` (or `/usr/local/bin` or whichever directory your other ZM perl scripts are installed).
- Move `zmeventnotification.ini` to `/etc`
- If you are using hook scripts, move the hook scripts to the path you specified in your ini file. Make sure they are executable.

**NOTE** : Starting version 1.32.0 of ZoneMinder, you now have an option to directly enable this daemon as an option directly in the settings of Options->Systems. Just enable "OPT_USE_EVENTNOTIFICATION" and you are all set.
**The rest of this section is NOT NEEDED for 1.32.0 and above!**

**WARNING** : Do NOT do this before you run it manually as I've mentioned above to test. Make sure it works, all packages are present etc. before you
add it as a daemon as if you don't and it crashes you won't know why

(Note if you have compiled from source using cmake, the paths may be `/usr/local/bin` not `/usr/bin`)

- Edit `/usr/bin/zmdc.pl` and in the array `@daemons` (starting line 89 or so, may change depending on ZM version) add `'zmeventnotification.pl'` like [this](https://gist.github.com/pliablepixels/18bb68438410d5e4b644)
- Edit `/usr/bin/zmpkg.pl` and around line 275 (exact line # may change depending on ZM version), right after the comment that says `#this is now started unconditionally` and right before the line that says `runCommand( "zmdc.pl start zmfilter.pl" );` start zmeventnotification.pl by adding `runCommand( "zmdc.pl start zmeventnotification.pl" );` like [this](https://gist.github.com/pliablepixels/b4e4fd38ac526c5c881ee55da05195ff)
- Make sure you restart ZM. Rebooting the server is better - sometimes zmdc hangs around and you'll be wondering why your new daemon hasn't started
- To check if its running do a `zmdc.pl status zmeventnotification.pl`

You can/should run it manually at first to check if it works

## How can I use this with Node-Red or Home Assistant?

As of version 1.1, the event server also supports MQTT (Contributed by [@vajonam](https://github.com/vajonam)).
zmeventnotification server can be configured to broadcast on a topic called `/zoneminder/<monitor-id>` which can then be consumed by Home Assistant or Node-Red.

To enable this, set `enable = 1` under the `[mqtt]` section and specify the `server` to broadcast to.

You will also need to install the following module for this work

```
perl -MCPAN -e "install Net::MQTT::Simple"
```

## Disabling security

While I don't recommend either, several users seem to be interested in the following

- To run the eventserver on Websockets and not Secure Websockets, use `enable = 0` in the `[ssl]` section of the configuration file.
- To disable ZM Auth checking (be careful, anyone can get all your data INCLUDING passwords for ZoneMinder monitors if you open it up to the Internet) use `enable = 0` in the `[auth]` section of the configuration file.

## How do I safely upgrade zmeventserver to new versions?

```
sudo zmdc.pl stop zmeventnotification.pl
```

Now copy the new zmeventnotification.pl to the right place (usually `/usr/bin`)
If you need to, copy the new zmeventnotification.ini to the right place (usually `/etc`) (Note: this will replace your old config file and you shouldn't need to do this)

```
sudo zmdc.pl start zmeventnotification.pl
```

Make sure you look at the syslogs to make sure its started properly

## Configuring the notification server

### Understanding zmeventnotification configuration

Starting v1.0, [@synthead](https://github.com/synthead) reworked the configuration as follows:

- If you just run `zmeventnotification.pl` it will try and load `/etc/zmeventnotification.ini`. If it doesn't find it, it will use internal defaults
- If you want to override this with another configuration file, use `zmeventnotification.pl --config /path/to/your/config/filename.ini`. If you do choose to do this, please make sure you add `--config path/file` to `zmdc.pl` and `zmpkg.pl` when you add the daemons as per the [daemon section](#running-it-as-a-daemon-so-it-starts-automatically-along-with-zoneminder)
- If you run `zmeventnotification` you can also choose to use command line arguments to override specific variables. This may be helpful when debugging. Do a `zmeventnotification.pl --help` for all options
- Its always a good idea to validate you config settings. For example:

```
sudo /usr/bin/zmeventnotification.pl --check-config

03/31/2018 16:52:23.231955 zmeventnotification[29790].INF [using config file: /etc/zmeventnotification.ini]
Configuration (read /etc/zmeventnotification.ini):

Port .......................... 9000
Address ....................... XX.XX.XX.XX
Event check interval .......... 5
Monitor reload interval ....... 300

Auth enabled .................. true
Auth timeout .................. 20

Use FCM ....................... true
FCM API key ................... (defined)
Token file .................... /etc/private/tokens.txt

SSL enabled ................... true
SSL cert file ................. /etc/apache2/ssl/zoneminder.crt
SSL key file .................. /etc/apache2/ssl/zoneminder.key

Verbose ....................... false
Read alarm cause .............. true
Tag alarm event id ............ false
Use custom notification sound . false

Hook .......................... '/usr/bin/person_detect_wrapper.sh'
Use Hook Description........... true
```

### What is the hook attribute ?

The `hook` attribute allows you to invoke a custom script when an alarm is triggered by ZM. 
If the script returns success (exit value of 0) then the notification server will send out an alarm notification. If not, it will not send a notification to 
its listeners. This is useful to implement any custom logic you may want to perform that decides whether this event is worth sending a notification for.

Related to `hook` we also have a `hook_description` attribute. When set to 1, the text returned by the hook script will overwrite the alarm text that is notified.

Here is an example:
(Note: just an example, please don't ask me for support for person detection)

- You will find a sample `detect_wrapper.sh` hook in the `hook_example` directory. This script is invoked by the notification server when an event occurs.
- This script in turn invokes a python OpenCV based script that grabs an image with maximum score from the current event so far and runs a fast person detection routine.
- It returns the value "person detected" if a person is found and none if not
- The wrapper script then checks for this value and exits with either 0 (send alarm) or 1 (don't send alarm)
- the notification server then sends out a "<Monitor Name>: person detected" notification to the clients listening

Those who want to know more:
- Read the detailed notes [here](https://github.com/pliablepixels/zmeventserver/tree/master/hook_example)
- Read [this](https://medium.com/zmninja/inside-the-hood-machine-learning-enhanced-real-time-alarms-with-zoneminder-e26c34fe354c) for an explanation of how this works

## Troubleshooting common situations



### Picture notifications don't show images

Starting v2.0, I support images in alarms. However, there are several conditions to be met:
* Works only on Android for now
* You can't use self signed certs
* You need patches to ZM unless you are using a package that is later than Oct 11, 2018. Please read the notes in the INI file 

### Secure mode just doesn't work (WSS) - WS works

Try to put in your event server IP in the `address` token in `[network]` section of `zmeventnotification.ini`

### I'm not receiving push notifications in zmNinja

This almost always happens when zmNinja is not able to reach the server. Before you contact me, please perform the following steps and send me the output: 

1. Stop the event server. `sudo zmdc.pl stop zmeventnotification.pl`
2. Do a `ps -aef | grep zmevent` and make sure no stale processes are running
3. Edit your `/etc/zmeventnotification.ini` and make sure `verbose = 1` to get verbose logs
4. Run the server manually by doing `sudo -u www-data /usr/bin/zmeventnotification.pl` (replace with `www-data` with `apache` depending on your OS)
5. You should now see logs on the commandline like so that shows the server is running:

```
018-12-20,08:31:32 About to start listening to socket
12/20/2018 08:31:32.606198 zmeventnotification[12460].INF [main:582] [About to start listening to socket]
2018-12-20,08:31:32 Secure WS(WSS) is enabled...
12/20/2018 08:31:32.656834 zmeventnotification[12460].INF [main:582] [Secure WS(WSS) is enabled...]
2018-12-20,08:31:32 Web Socket Event Server listening on port 9000
12/20/2018 08:31:32.696406 zmeventnotification[12460].INF [main:582] [Web Socket Event Server listening on port 9000]
```

6. Now start zmNinja. You should see event server logs like this:

```
2018-12-20,08:32:43 Raw incoming message: {"event":"push","data":{"type":"token","platform":"ios","token":"cVuLzCBsEn4:APA91bHYuO3hVJqTIMsm0IRNQEYAUa<deleted>GYBwNdwRfKyZV0","monlist":"1,2,4,5,6,7,11","intlist":"45,60,0,0,0,45,45","state":"enabled"}}
```
If you don't see these logs on the event server, zmNinja is not able to connect to the event server. This may be because of several reasons:
a) Your event server IP/DNS is not reachable from your phone
b) If you are using SSL, your certificates are invalid (try disabling SSL first - both on the event server and on zmNinja)
c) Your zmNinja configuration is wrong (the most common error I see is the server has SSL disabled, but zmNinja is configured to use `wss://` instead of `ws://`)

7. Assuming the above worked, go to zmNinja logs in the app. Somewhere in the logs, you should see a line similar to:

```
Dec 20, 2018 05:50:41 AM DEBUG Real-time event: {"type":"","version":"2.4","status":"Success","reason":"","event":"auth"}
```

This indicates that the event server successfully authenticated the app. If you see step 6 work but not step 7, you might have provided incorrect credentials (and in that case, you'll see an error message)

8. Finally, after all of the above succeeds, do a `cat /etc/private/tokens.txt` to make sure the device token that zmNinja sent is stored (desktop apps don't have a device token). If you are using zmNinja on a mobile app, and you don't see an entry in `tokens.txt` you have a problem. Debug.
   
9.   _Always_ send me logs of both zmNinja and zmeventserver - I need them to understand what is going on. Don't send me one line. You may think you are sending what is relevant, but you are not. One line logs are mostly useless.

10. Some other notes:

- If you don't see an entry in `tokens.txt` (typically in `/etc/private`) then your phone is not registered to get push. Kill zmNinja,
  start the app, make sure the event server receives the registration and check `tokens.txt`

- Sometimes, Google's FCM server goes down, or Apple's APNS server goes down for a while. Things automagically work in 24 hrs.


- Kill the app. Then empty the contents of `tokens.txt` in the event server (don't delete it). Then restart the event server. Start the app again. If you don't see a new registration token, you have a connection problem


- I'd strongly recommend you run the event server in "manual mode" and stop daemon mode while debugging.

### I'm getting multiple notifications for the same event

99.9% of times, its because you have multiple copies of the eventserver running and you don't know it. Maybe you were manually testing it, and forgot
to quit it and terminated the window. Do `sudo zmdc.pl stop zmeventnotification.pl` and then  `ps -aef | grep zme`, kill everything, and start again. 
Monitor the logs to see how many times a message is sent out. 

The other 0.1% is at times Google's FCM servers send out multiple notifications. Why? I don't know. But it sorts itself out very quickly, and if you think
this must be the reason, I'll wager that you are actually in the 99.9% lot and haven't checked properly.


### The server runs fine when manually executed, but fails when run in daemon mode (started by zmdc.pl)

- Make sure the file where you store tokens (`/etc/private/tokens.txt or whatever you have used`) is not RW Root only. It needs to be RW `www-data` for Ubuntu/Debian or `apache` for Fedora/CentOS. You also need to make sure the directory is accessible. Something like `chown -R www-data:www-data /etc/private`

- Make sure your certificates are readable by `www-data` for Ubuntu/Debian, or `apache` for Fedora/CentOS (thanks to [@jagee](https://github.com/pliablepixels/zmeventserver/issues/8))
- Make sure the _path_ to the certificates are readable by `www-data` for Ubuntu/Debian, or `apache` for Fedora/CentOS

### When you run zmeventnotifiation.pl manually, you get an error saying 'port already in use' or 'cannot bind to port' or something like that

The chances are very high that you have another copy of `zmeventnotification.pl` running. You might have run it in daemon mode. Try `sudo zmdc.pl stop zmeventnotification.pl`. Also do `ps -aef | grep zmeventnotification` to check if another copy is not running and if you do find one running, you'll have to kill it before you can start it from command line again.

### Great Krypton! I just upgraded ZoneMinder and I'm not getting push anymore!

Make sure your eventserver is running: `sudo zmdc.pl status zmeventnotification.pl`

## How do I disable secure (WSS) mode?

As it turns out many folks run ZM inside the LAN only and don't want to deal with certificates. Fair enough.
For that situation, edit zmeventnotification.pl and use `enable = 0` in the `[ssl]` section of the configuration file.
**Remember to ensure that your EventServer URL in zmNinja does NOT use wss too - change it to ws**

## Debugging and reporting problems

STOP. Before you shoot me an email, **please** make sure you have read the [common problems](#troubleshooting-common-situations) and have followed _every step_ of the [install guide](#how-do-i-install-it) and in sequence. I can't emphasize how important it is.

There could be several reasons why you may not be receiving notifications:

- Your event server is not running
- Your app is not able to reach the server
- You have enabled SSL but the certificate is invalid
- The event server is rejecting the connections

Here is how to debug and report:

- Enable Debug logs in zmNinja (Setting->Developer Options->Enable Debug Log)
- telnet/ssh into your zoneminder server
- Stop the zmeventnotification doing `sudo zmdc.pl stop zmeventnotification.pl`
- Make sure there are no stale processes running of zmeventnotification by doing `ps -aef | grep zmeventnotification` and making sure it doesn't show existing processes (ignore the one that says `grep <something>`)
- Edit `zmeventnotification.ini` (typically in `/etc/`) and make sure `verbose = 1` is set. This will print more logs on the console. Make sure you turn this off again before switching back to daemon mode.
- Start a terminal (lets call it Terminal-Log) to tail logs like so `tail -f /var/log/syslog | grep zmeventnotification`
- Start another terminal and start zmeventserver manually from command line like so `sudo /usr/bin/zmeventnotification.pl`
- Make sure you see logs like this in the logs window like so:

```
Nov 26 14:27:20 homeserver zmdc[18560]: INF ['zmeventnotification.pl' started at 17/11/26 14:27:20]
Nov 26 14:27:20 homeserver zmeventnotification[18560]: INF [Push enabled via FCM]
Nov 26 14:27:20 homeserver zmeventnotification[18560]: INF [Event Notification daemon v 0.95 starting]
Nov 26 14:27:20 homeserver zmeventnotification[18560]: INF [Total event client connections: 3]
Nov 26 14:27:20 homeserver zmeventnotification[18560]: INF [Reloading Monitors...]
Nov 26 14:27:21 homeserver zmeventnotification[18560]: INF [Loading monitors]
Nov 26 14:27:21 homeserver zmeventnotification[18560]: INF [About to start listening to socket]
Nov 26 14:27:21 homeserver zmeventnotification[18560]: INF [Secure WS(WSS) is enabled...]
Nov 26 14:27:21 homeserver zmeventnotification[18560]: INF [Web Socket Event Server listening on port 9000]
```

- Open up zmNinja, clear logs
- Enable event server in zmNinja
- Check that when you save the event server connections in zmNinja, you see logs in the log window like this

```
Oct 20 10:23:18 homeserver zmeventnotification[27789]: INF [got a websocket connection from XX.XX.XX.XX (11) active connections]
Oct 20 10:23:18 homeserver zmeventnotification[27789]: INF [Websockets: New Connection Handshake requested from XX.XX.XX.XX:55189 state=pending auth]
Oct 20 10:23:18 homeserver zmeventnotification[27789]: INF [Correct authentication provided byXX.XX.XX.XX]
Oct 20 10:23:18 homeserver zmeventnotification[27789]: INF [Storing token ...9f665f182b,monlist:-1,intlist:-1,pushstate:enabled]
Oct 20 10:23:19 homeserver zmeventnotification[27789]: INF [Contrl: Storing token ...9f665f182b,monlist:1,2,4,5,6,7,10,intlist:0,0,0,0,0,0,0,pushstate:enabled]
```

If you don't see anything there is a connection problem. Review SSL guidelines above, or temporarily turn off websocket SSL as described above

- Open up ZM console and force an alarm, you should see logs in your log window above like so:

```
Oct 20 10:28:55 homeserver zmeventnotification[27789]: INF [New event 32910 reported for Garage]
Oct 20 10:28:55 homeserver zmeventnotification[27789]: INF [Broadcasting new events to all 12 websocket clients]
Oct 20 10:28:55 homeserver zmeventnotification[27789]: INF [Checking alarm rules for  token ending in:...2baa57e387]
Oct 20 10:28:55 homeserver zmeventnotification[27789]: INF [Monitor 1 event: last time not found, so sending]
Oct 20 10:28:55 homeserver zmeventnotification[27789]: INF [Sending notification over PushProxy]
Oct 20 10:28:56 homeserver zmeventnotification[27789]: INF [Pushproxy push message success ]
```

- If you are debugging problems with receiving push notifications on zmNinja mobile, then replicate the following scenario:

  - Run the event server in manual mode as described above
  - Kill zmNinja
  - Start zmNinja
  - At this point, in the `zmeventnotification` logs you should registration messages (refer to logs example above). If you don't you've either not configured zmNinja to use the eventserver, or it can't reach the eventserver (very common problem)
  - Next up, make sure you are not running zmNinja in the foreground (move it to background or kill it). When zmNinja is in the foreground, it uses websockets to get notifications
  - Force an alarm like I described above. If you don't see logs in `zmeventnotification` saying "Sending notification over PushProxy" then the eventserver, for some reason, does not have your app token. Inspeced `tokens.txt` (typically in `/etc/`) to make sure an entry for your phone exists
  - If you see that message, but your mobile phone is not receiving a push notification:
  - Make sure you haven't disable push notifications on your phone (lots of people do this by mistake and wonder why)
  - Make sure you haven't muted notifications (again, lots of people...)
  - Sometimes, the push servers of Apple and Google stop forwarding messages for a day or two. I have no idea why. Give it a day or two?
  - Open up zmNinja, go right to logs and send it to me

- If you have issues, please send me a copy of your zmeventserver logs generated above from Terminal-Log, as well as zmNinja debug logs

## For Developers writing their own consumers
    
### How do I talk to it?
*  `{"JSON":"everywhere"}`
* Your client sends messages (authentication) over JSON
* The server sends auth success/failure over JSON back at you
* New events are reported as JSON objects as well
* By default the notification server runs on port 9000 (unless you change it)
* You need to open a secure web socket connection to that port from your client/consumer
* You then need to provide your authentication credentials (ZoneMinder username/password) within 20 seconds of opening the connection
* If you provide an incorrect authentication or no authentication, the server will close your connection
* As of today, there are 3 categories of message types your client (zmNinja or your own) can exchange with the server (event notification server)
 1. auth (from client to server)
 2. control (from client to server)
 3. push (only applicable for zmNinja)
 4. alarm (from server to client)

#### Authentication messages

To connect with the server you need to send the following JSON object (replace username/password)
Note this payload is NOT encrypted. If you are not using SSL, it will be sent in clear.

Authentication messages can be sent multiple times. It is necessary that you send the first one
within 20 seconds of opening a connection or the server will terminate your connection.

**Client --> Server:**

```
{"event":"auth","data":{"user":"<username>","password":"<password>"}}
```

**Server --> Client:**
The server will send back one of the following responses

Authentication successful:

```
{"event":"auth", "type":"", "version":"0.2","status":"Success","reason":""}
```

Note that it also sends its version number for convenience

Incorrect credentials:

```
{"event":"auth", "type":"", "status":"Fail","reason":"BADAUTH"}
```

No authentication received in time limit:

```
{"event":"auth","type":"", "status":"Fail","reason":"NOAUTH"}
```

#### Control messages

Control messages manage the nature of notifications received/sent. As of today, Clients send control messages to the Server.
In future this may be bi-directional

##### Control message to restrict monitor IDs for events as well as interval durations for reporting

A client can send a control message to restrict which monitor IDs it is interested in. When received, the server will only
send it alarms for those specific monitor IDs. You can also specify the reporting interval for events.

**Client-->Server:**

```
{"event":"control","data":{"type":"filter","monlist":"1,2,4,5,6", "intlist":"0,0,3600,60,0"}}
```

In this example, a client has requested to be notified of events only from monitor IDs 1,2,4,5 and 6
Furthermore it wants to be notified for each alarm for monitors 1,2,6. For monitor 4, it wants to be
notified only if the time difference between the previous and current event is 1 hour or more (3600 seconds)
while for monitor 5, it wants the time difference between the previous and current event to be 1 minute (60 seconds)

There is no response for this request, unless the payload did not have either monlist or intlist.

No monitorlist received:

```
{"event":"control","type":"filter", "status":"Fail","reason":"NOMONITORLIST"}
```

No interval received:

```
{"event":"control","type":"filter", "status":"Fail","reason":"NOINTERVALLIST"}
```

Note that if you don't want to specify intervals, send it a interval list comprising of comma separated 0's, one for each monitor in monitor list.

##### Control message to get Event Server version

A client can send a control message to request Event Server version

**Client-->Server:**

```
{"event":"control","data":{"type":"version"}}
```

**Server-->Client:**

```
{"event":"control", "type:":"version", "version":"0.2","status":"Success","reason":""}
```

#### Alarm notifications

Alarms are events sent from the Server to the Client

**Server-->Client:**
Sample payload of 2 events being reported:

```
{"event":"alarm", "type":"", "status":"Success", "events":[{"EventId":"5060","Name":"Garage","MonitorId":"1"},{"EventId":"5061","MonitorId":"5","Name":"Unfinished"}]}
```

#### Push Notifications (for both iOS and Android)

To make Push Notifications work, please make sure you read the [section on enabling Push](https://github.com/pliablepixels/zmeventserver#44-apnsgcm-howto---only-applicable-for-zmninja-not-for-other-consumers) for the event server.

##### Concepts of Push and why it is only for zmNinja

Both Apple and Google ensure that a "trusted" application server can send push notifications to a specific app running in a device. If they did not require this, anyone could spam apps with messages. So in other words, a "Push" will be routed from a specific server to a specific app. Starting Jan 2018, I am hosting my trusted push server on Google's Firebase cloud. This eliminates the need for me to run my own server.

##### Registering Push token with the server

**Client-->Server:**

Registering an iOS device:

```
{"event":"push","data":{"type":"token","platform":"ios","token":"<device tokenid here>", "state":"enabled"}}
```

Here is an example of registering an Android device:

```
{"event":"push","data":{"type":"token","platform":"android","token":"<device tokenid here>", "state":"enabled"}}
```

For devices capable of receiving push notifications, but want to stop receiving push notifications over APNS/GCM
and have it delivered over websockets instead, set the state to disabled

For example:
Here is an example of registering an Android device, which disables push notifications over GCM:

```
{"event":"push","data":{"type":"token","platform":"android","token":"<device tokenid here>", "state":"disabled"}}
```

What happens here is if there is a new event to report, the Event Server will send it over websockets. This means
if the app is running (foreground or background in Android, foreground in iOS) it will receive this notification
over the open websocket. Note that in iOS this means you won't receive notifications when the app is not running
in the foreground. We went over why, remember?

**Server-->Client:**
If its successful, there is no response. However, if Push is disabled it will send back

```
{"event":"push", "type":"", "status":"Fail", "reason": "PUSHDISABLED"}
```

##### Badge reset

Only applies to iOS. Android push notifications don't have a concept of badge notifications, as it turns out.

In push notifications, the server owns the responsibility for badge count (unlike local notifications).
So a client can request the server to reset its badge count so the next push notification
starts from the value provided.

**Client-->Server:**

```
{"event":"push", "data":{"type":"badge", "badge":"0"}}
```

In this example, the client requests the server to reset the badge count to 0. Note that you
can use any other number. The next time the server sends a push via APNS, it will use this
value. 0 makes the badge go away.

#### Testing from command line

If you are writing your own consumer/client it helps to test the event server commands from command line.
The event server uses Secure/WebSockers so you can't just HTTP to it using tools like `curl`. You'll need to
use a websocket client. While there are examples on the net on how to use `curl` for websockets, I've found it
much simpler to use [wscat](https://github.com/websockets/wscat) like so:

```
wscat -c wss://myzmeventserver.domain:9000 -n
connected (press CTRL+C to quit)
> {"event":"auth","data":{"user":"admin","password":"xxxx"}}
< {"reason":"","status":"Success","type":"","event":"auth","version":"0.93"}
```

In the example above, I used `wscat` to connect to my event server and then sent it a JSON login message which it accepted and acknowledged.

## How scalable is it?

It's a lightweight single threaded process. I really don't see a need for launching a zillion threads or a process per monitor etc for what it does. I'd argue its simplicity is its scalability. Plus I don't expect more than a handful of consumers to connect to it. I really don't see why it won't be able to scale to for what is does. But if you are facing scalability issues, let me know. There is [Mojolicious](http://mojolicio.us/) I can use to make it more scalable if I am proven wrong about scalability.

## Brickbats

**Why not just supply the username and password in the URL as a resource? It's over TLS**

Yup its encrypted but it may show up in the history of a browser you tried it from (if you are using a browser)
Plus it may get passed along from the source when accessing another URL via the Referral header

**So it's encrypted, but passing password is a bad idea. Why not some token?**

- Too much work.
- Plus I'm an unskilled programmer. Pull Requests welcome

**Why WSS and not WS?**

Not secure. Easy to snoop.
Updated: As of 0.6, I've also added a non secure version - use `enable = 0` in the `[ssl]` section of the configuration file.
As it turns out many folks don't expose ZM to the WAN and for that, I guess WS instead of WSS is ok.

**Why ZM auth in addition to WSS?**

WSS offers encryption. We also want to make sure connections are authorized. Reusing ZM authentication credentials is the easiest. You can change it to some other credential match (modify `validateZM` function)

