### Note

This is just an example of how you can use the new `hook` feature of the notification server
to invoke a custom script on the event before it generates an alarm. This implements a hook script that detects
for persons in an image that raised an alarm before sending out a notification. The detection uses a very fast, but
not very accurate OpenCV model (hog.detectMultiScale). The good part is that it is extremely fast can can be used
for realtime needs. Fiddle with the settings in detect.py (stride/scale) to get more accuracy at the cost of speed.

Please don't expect this to work out of the box. You will need to read, change paths in the wrapper script
and make sure you have all the python modules installed. Please don't ask me for help unless you show me
you've tried hard enough

As always, if you are trying to figure out how this works, run zmeventnotification in MANUAL mode:

* `sudo zmdc.pl start zmeventnotification.pl`
*  change verbose to 1 in `zmeventnotification.ini`
*  `sudo -u www-data ./zmeventnotification.pl  --config ./zmeventnotification.ini`


