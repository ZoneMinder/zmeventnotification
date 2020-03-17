Key Principles - Event Notification Server  and Hooks
=======================================================

Summary
-------
This guide is meant to give you an idea of how the Event Notification Server (ES) works, how it invokes hooks and how notifications are finally sent out.

1: How it starts
----------------------
The ES is a perl process (typically ``/usr/bin/zmeventnotification.pl``) that acts like just any other ZM daemon (there are many) that is started by ZoneMinder when it starts up. Specifically, the ES gets "auto-started" only if you have enabled ``OPT_USE_EVENT_NOTIFICATION`` in your ``Zoneminder->System`` menu options. Technically, ZM uses a 'control' process called ``zmdc.pl`` that starts a bunch of important daemons (see `here <https://github.com/ZoneMinder/zoneminder/blob/release-1.34/scripts/zmdc.pl.in#L93>`__ for a list of daemons) and keeps a tab on them. If any of them die, they get restarted.

.. sidebar:: Configuration files
    
    This may be a good place to talk about configuration files. The ES has many customizations that are controlled by ``/etc/zm/zmeventnotification.ini``. If you are using hooks, they are controlled by ``/etc/zm/objectconfig.ini``. Both these files use ``/etc/zm/secrets.ini`` to move personal information away from config files. Study both these ini files well. They are heavily commented for your benefit.

2: Detecting New Events
-----------------------------
Once the ES is up and running, it uses shared memory to know when new events are reported by ZM. Basically, ZM writes data to shared memory (SHM) whenever a new event is detected. The ES regularly polls this memory to detect new events. This has 2 important side effects:

* The ES *must* run on the same server that ZM is running on. If you are using a multi-server system, you need an ES *per* server.
* If an event starts and ends before the ES checks SHM, this event may be missed. If you are seeing that happening, reduce ``event_check_interval`` in ``zmeventnotification.ini``. By default this is set to 5 seconds, which means events that open and close in a span of 5 seconds have a potential of being missed, if they start immediately after the ES checks for new events.

3: Deciding what to do when a new event starts
-----------------------------------------------------
When the ES detects a new event, it forks a sub-process to handle that event and continues its loop to listening for new events (by polling SHM). There is exactly one fork for each new event and that fork typically lives till the event is completely finished.

Step 3.1: Hooks (Optional)
***************************

If you are *not* using hooks, that is ``use_hooks=no`` in ``/etc/zm/zmeventnotification.ini`` then directly skip to the next section.

The entire concept of hooks is to "influence" whether or not to actually send out a notification for a new event. If you are already using hooks, you are likely using the most popular hook that I wrote, which actually does object/person/face detection on the image(s) that constitute the event to make an intelligent decision on whether you really want to be notified of the event. If you recall, the initial reason why I wrote the ES was to send "push notifications" to zmNinja. You'd be inundated if you got a push for *every* new event ZM reports. 

So when you have hooks enabled, the script that is invoked when a new event is detected by the ES is defined in ``event_start_hook`` inside ``zmeventnotification.ini``. I am going to assume you did not change that hook script, because the default script does the fancy image recognition that lot of people love. That script, which is usually ``/var/lib/zmeventnotification/bin/zm_event_start.sh`` does the following:

* It invokes `/var/lib/zmeventnotification/bin/zm_detect.py` that is the actual script that does the fancy detection and waits for a response. If this python file detects objects that meet the criteria in ``/etc/zm/objectconfig.ini`` it will return an exit code of ``0`` (success) with a text string describing the objects, else it will return an exit code of ``1`` (fail) 
* It passes on the output and the return value of the script back to the ES

The ES has no idea what the event start script does. All it cares about is the "return value". If it returns ``0`` that means the hook "succeeded" and if it returned any non ``0`` value, the script failed. This return code makes a difference on whether the final notification is sent out or not, as you will see later.

3.2: Will the ES send a notification?
********************************************
So at this stage, we have a new event and we need to decide if the ES will send out a notification. The following factors matter:

- If you had hooks enabled, and the hook succeeded (i.e. return value of ``0``), then the notification *may* be sent to the channels you specified in ``event_start_notify_on_hook_success``. If the hook failed (i.e. return value of non zero, then the notification *may* be sent to the channels specified in ``event_start_notify_on_hook_fail``)

3.2.1: Wait what is a channel?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
At a high level, there are 3 types of clients that are interested in receiving notifications:

* zmNinja: the mobile app that uses Firebase Cloud Messaging (FCM) to get push notifications. This is the "fcm" channel
* Any websocket client: This included zmNinja desktop and any other custom client you may have written to get notifications via web sockets. This is the "web" channel
* Any 3rd party push solution which you may be using to deliver push notifications. A popular one is "pushover" for which I provide a `plugin <https://github.com/pliablepixels/zmeventnotification/blob/master/pushapi_plugins/pushapi_pushover.py>`__. This is the "api" channel.

So, for example:

::

  event_start_notify_on_hook_success = all
  event_start_notify_on_hook_fail = api,web

This will mean when a new event occurs, everyone may get a notification if the hook succeeded but if the hook fails, only API  and Web channels will be notified, not FCM. This means zmNinja mobile app will not be notified. Obviously, if you don't want to get deluged with constant notifications on your phone, don't put ``fcm`` as a channel in ``event_Start_notify_on_hook_fail``.

3.2.2: The tokens.txt file
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Why do I say above that you *may* get a notification?

You'd think if the channels conditions are met and the hook conditions are met, then those channels *will* get a notification. Not quite. 

.. note::

    There is another "configuration" file that impacts this decision process. This only applies to the "fcm" channel and is not documented very much. So read this section well.

There is another file, ``/var/lib/zmeventnotification/push/tokens.txt`` that dictates if events are finally sent or not. This pre-dates all the hook stuff and was created really so that zmNinja could receive notifications from the ES.

This file is actually created  when zmNinja sets up push notification. Here is how it works:

* When zmNinja runs and you enable push notifications, it asks either Apple or Google for a unique token to receive notifications via their push servers. 
* This token is then sent to the ES via websockets. The ES stores this token in the ``tokens.txt`` file and everytime it restarts, it reloads these tokens so it knows these clients expect notifications over FCM. **So if your zmNinja app cannot connect to the ES for the first time, the token will never be saved and the ES will never be able to send notifications to your zmNinja app**.

However, there are other things the ``tokens.txt`` file saves. Let's take a look:

Here is a typical tokens.txt entry:

::
          
  es<long token>tMj:1,2,5:0,120,120:ios:enabled
  d9K<long token>jAZxhUKqh:1,2,5,6,7,8,9,10,11:0,0,0,0,0,0,0,0,0:android:disabled


The contents above show I have 2 devices configured, one is an iOS device and the other is an android device. But lets look at the other fields (separated by ``:``)

* column 1 = unique token, we discussed this above
* column 2 = list of monitors that will be processed for events for this connection. For example, in the first row, this device will ONLY get notifications for monitors 1,2,5
* column 3 = interval in seconds before the next notification is sent. If we look at the first row, it says monitor 1 events will be sent as soon as they occur, however for monitor 2 and 5, notifications will only be sent if the previous notification for that monitor was *at least* 120 seconds before (2 mins). How is this set? You actually set it via zmNinja->Settings->Event Server Settings
* column 4: the device type (we need this to create a push notification message correctly)
* column 5: Finally, this tells us if push is enabled or disabled for this device. There are two ways to disable - you can disable push notifications for zmNinja on your device, or you can simply uncheck "use event server" in zmNinja. This is for the latter case. If you uncheck "use event server", we need to be able to tell the ES that even though it has a token on file, it should not send notifications.

.. important::

    It is important to note here that if zmNinja is not able to connect to the ES at least for the first time, you will never receive notifications. Check your ``tokens.txt`` file to make sure you have entries. If you don't that means zmNinja can't reach your ES.

  
   
