# Changelog

## [v5.1.2](https://github.com/pliablepixels/zmeventnotification/tree/v5.0.1) (2019-12-19)

[Full Changelog](https://github.com/pliablepixels/zmeventnotification/compare/v4.6.1...v5.0.1)

**Implemented enhancements:**

- Allow object detection to be run remotely [\#184](https://github.com/pliablepixels/zmeventnotification/issues/184)
- Support pre/post event hooks, also support specific channels for notification after hook or  fail [\#180](https://github.com/pliablepixels/zmeventnotification/issues/180)
- Support multiple faces per person  [\#173](https://github.com/pliablepixels/zmeventnotification/issues/173)

**Fixed bugs:**

- Yolo minimum confidence is hard coded to 0.5 in code, will not go lower but higher works [\#178](https://github.com/pliablepixels/zmeventnotification/issues/178)

**Closed issues:**

- bad bcrypt settings at ./zmeventnotification.test.pl line 938 [\#182](https://github.com/pliablepixels/zmeventnotification/issues/182)
- MQTT Enhancement [\#179](https://github.com/pliablepixels/zmeventnotification/issues/179)
- FR: ZmNinja - Zmeventnotification selection [\#152](https://github.com/pliablepixels/zmeventnotification/issues/152)

**Merged pull requests:**

- Dev [\#181](https://github.com/pliablepixels/zmeventnotification/pull/181) ([pliablepixels](https://github.com/pliablepixels))

## [v4.6.1](https://github.com/pliablepixels/zmeventnotification/tree/v4.6.1) (2019-11-21)

[Full Changelog](https://github.com/pliablepixels/zmeventnotification/compare/v4.5.8...v4.6.1)

**Implemented enhancements:**

- Allow for secret tokens to be used in ES and OD configs [\#167](https://github.com/pliablepixels/zmeventnotification/issues/167)

**Fixed bugs:**

- ZMES stops working after a few hours  [\#177](https://github.com/pliablepixels/zmeventnotification/issues/177)

**Closed issues:**

- detect.py is failing with \_urllib.error.URLError: \<urlopen error no host given\>\_ [\#172](https://github.com/pliablepixels/zmeventnotification/issues/172)
- What version of OpenCV does Machine Learning Hook need? [\#171](https://github.com/pliablepixels/zmeventnotification/issues/171)
- Delete events if no person is detected [\#164](https://github.com/pliablepixels/zmeventnotification/issues/164)

**Merged pull requests:**

- Hangup debug [\#176](https://github.com/pliablepixels/zmeventnotification/pull/176) ([pliablepixels](https://github.com/pliablepixels))
- Multiple face and clustering support [\#174](https://github.com/pliablepixels/zmeventnotification/pull/174) ([pliablepixels](https://github.com/pliablepixels))

## [v4.5.8](https://github.com/pliablepixels/zmeventnotification/tree/v4.5.8) (2019-11-06)

[Full Changelog](https://github.com/pliablepixels/zmeventnotification/compare/dccf3345a30cdc20f2fdef70bafa8bdf894fde76...v4.5.8)

**Implemented enhancements:**

- Add ability to ignore previously matched objects [\#121](https://github.com/pliablepixels/zmeventnotification/issues/121)
- Rework detection flow [\#109](https://github.com/pliablepixels/zmeventnotification/issues/109)
- Allow fid type per monitor [\#100](https://github.com/pliablepixels/zmeventnotification/issues/100)
- Query zm DB for zone info to create polygon areas for object detection [\#91](https://github.com/pliablepixels/zmeventnotification/issues/91)
- enable/disable sound and vibration push notifications. [\#11](https://github.com/pliablepixels/zmeventnotification/issues/11)
- Add an option to run zmeventnotification without SSL \(that is WS instead of WSS\) [\#6](https://github.com/pliablepixels/zmeventnotification/issues/6)

**Fixed bugs:**

- Password limitation in picture url [\#161](https://github.com/pliablepixels/zmeventnotification/issues/161)
- Event Server Configuration Target Directory isn't Displayed by install.sh [\#154](https://github.com/pliablepixels/zmeventnotification/issues/154)
- bad bcrypt settings at /usr/bin/zmeventnotification.pl line 769. [\#122](https://github.com/pliablepixels/zmeventnotification/issues/122)
- Continuous events: Problems arise when alarms occur multiple times during the course of an event. [\#114](https://github.com/pliablepixels/zmeventnotification/issues/114)
- Script using incorrect equivalence operator when checking event state [\#105](https://github.com/pliablepixels/zmeventnotification/issues/105)
- Can no longer set yolo\_type=tiny in objectconfig.ini [\#104](https://github.com/pliablepixels/zmeventnotification/issues/104)
- write to DB doesn't work if hook script duration exceeds alarm duration [\#73](https://github.com/pliablepixels/zmeventnotification/issues/73)
- DB text update for object detection fails for events that occur very close to each other [\#71](https://github.com/pliablepixels/zmeventnotification/issues/71)
- multiple concurrent event handling is broken [\#59](https://github.com/pliablepixels/zmeventnotification/issues/59)
- MQTT events are being concatenated [\#58](https://github.com/pliablepixels/zmeventnotification/issues/58)
- Events constantly sending - not waiting for 'mint', log always says "last time not found, so sending" [\#57](https://github.com/pliablepixels/zmeventnotification/issues/57)
- fix incorrect removal of tokens due to web socket errors [\#24](https://github.com/pliablepixels/zmeventnotification/issues/24)
- fix tokenization to allow for GCM tokens to have ":" [\#21](https://github.com/pliablepixels/zmeventnotification/issues/21)

**Closed issues:**

- Timing issue in object detection with snapshot or bestmatch?  [\#165](https://github.com/pliablepixels/zmeventnotification/issues/165)
- CNN model not working [\#162](https://github.com/pliablepixels/zmeventnotification/issues/162)
- Detected faces not displayed in zm event web UI [\#160](https://github.com/pliablepixels/zmeventnotification/issues/160)
- Get hook script returned exit:1 when called from zm, but works on commandline [\#159](https://github.com/pliablepixels/zmeventnotification/issues/159)
- Picture\_url not loading in Android notification [\#158](https://github.com/pliablepixels/zmeventnotification/issues/158)
- Issues with install and running zmeventnotification [\#157](https://github.com/pliablepixels/zmeventnotification/issues/157)
- detect.sh ZoneMinder API authentication problem [\#156](https://github.com/pliablepixels/zmeventnotification/issues/156)
- No mqtt events in daemon mode after zoneminder reinstallation [\#155](https://github.com/pliablepixels/zmeventnotification/issues/155)
- zmeventnotification stops sending notifications afer a few hours [\#153](https://github.com/pliablepixels/zmeventnotification/issues/153)
- Rights Issue with www-data [\#151](https://github.com/pliablepixels/zmeventnotification/issues/151)
- Documentation inconsistencies [\#149](https://github.com/pliablepixels/zmeventnotification/issues/149)
- setup.py fails because of wrong version of python 3.5 [\#148](https://github.com/pliablepixels/zmeventnotification/issues/148)
- Disabling auth doesn't seem to quite work [\#147](https://github.com/pliablepixels/zmeventnotification/issues/147)
- Hook pip3 install error [\#145](https://github.com/pliablepixels/zmeventnotification/issues/145)
- Can't exec: Bad file descriptor [\#143](https://github.com/pliablepixels/zmeventnotification/issues/143)
- Improve the match\_past\_detections feature [\#140](https://github.com/pliablepixels/zmeventnotification/issues/140)
- switch to Net::MQTT:Simple for authenticated connections as well.  [\#134](https://github.com/pliablepixels/zmeventnotification/issues/134)
- running detect\_wrapper.sh gives ImportError: No module named zmes\_hook\_helpers.log [\#133](https://github.com/pliablepixels/zmeventnotification/issues/133)
- fid=alarm doesn't work sometimes - question  [\#131](https://github.com/pliablepixels/zmeventnotification/issues/131)
- running detection in a container [\#128](https://github.com/pliablepixels/zmeventnotification/issues/128)
- MQTT doesn't work with RabbitMQ [\#125](https://github.com/pliablepixels/zmeventnotification/issues/125)
- declare my $new\_hash [\#124](https://github.com/pliablepixels/zmeventnotification/issues/124)
- Can't create frame capture images from video because there is no video file for this event [\#118](https://github.com/pliablepixels/zmeventnotification/issues/118)
- Issue Testing Detect.py [\#117](https://github.com/pliablepixels/zmeventnotification/issues/117)
- FCM push message Error:500 Server closed connection without sending any data back [\#112](https://github.com/pliablepixels/zmeventnotification/issues/112)
- Perl SSL error on manual first run [\#103](https://github.com/pliablepixels/zmeventnotification/issues/103)
- monitor specific object detect w/ import\_zm\_zones=yes [\#99](https://github.com/pliablepixels/zmeventnotification/issues/99)
- Getting zone information for monitors failed [\#98](https://github.com/pliablepixels/zmeventnotification/issues/98)
- Finding out what zone the event happened in [\#97](https://github.com/pliablepixels/zmeventnotification/issues/97)
- mqtt tag missing from ini file [\#92](https://github.com/pliablepixels/zmeventnotification/issues/92)
- "Stacking" Event Notifications\(Android\). [\#85](https://github.com/pliablepixels/zmeventnotification/issues/85)
- Race condition with download of alarm and snapshot files [\#82](https://github.com/pliablepixels/zmeventnotification/issues/82)
- ConfigParser python module missing [\#80](https://github.com/pliablepixels/zmeventnotification/issues/80)
- devtree readme bad link [\#76](https://github.com/pliablepixels/zmeventnotification/issues/76)
- delay next event [\#67](https://github.com/pliablepixels/zmeventnotification/issues/67)
- Add Alarmimage as mqtt payload [\#66](https://github.com/pliablepixels/zmeventnotification/issues/66)
- use\_hook\_description doesnt always work..  [\#65](https://github.com/pliablepixels/zmeventnotification/issues/65)
- Secure connection with Letsencrypt certificate [\#64](https://github.com/pliablepixels/zmeventnotification/issues/64)
- Pass alarm cause to the hook [\#63](https://github.com/pliablepixels/zmeventnotification/issues/63)
- sending image with ios notification [\#62](https://github.com/pliablepixels/zmeventnotification/issues/62)
- Not receiving MQTT messages [\#56](https://github.com/pliablepixels/zmeventnotification/issues/56)
- Not receiving event notifications after upgrading zmeventnotification.pl to 1.2  [\#54](https://github.com/pliablepixels/zmeventnotification/issues/54)
- filter for event push [\#50](https://github.com/pliablepixels/zmeventnotification/issues/50)
- I would like to receive event notifications in node red, is there a workflow for this?  [\#49](https://github.com/pliablepixels/zmeventnotification/issues/49)
- Minor README.md corrections [\#48](https://github.com/pliablepixels/zmeventnotification/issues/48)
- SSL Problem  [\#47](https://github.com/pliablepixels/zmeventnotification/issues/47)
- no live view or montage view inzmNinja [\#46](https://github.com/pliablepixels/zmeventnotification/issues/46)
- 	Config::Inifiles missing [\#45](https://github.com/pliablepixels/zmeventnotification/issues/45)
- Unable to get ssl connection in Ubuntu Docker [\#43](https://github.com/pliablepixels/zmeventnotification/issues/43)
- Rework zmeventserver initialization, move to ini file [\#42](https://github.com/pliablepixels/zmeventnotification/issues/42)
- Support for IPv6 dualstack [\#39](https://github.com/pliablepixels/zmeventnotification/issues/39)
- Bad authentication provided [\#38](https://github.com/pliablepixels/zmeventnotification/issues/38)
- daemon not work [\#37](https://github.com/pliablepixels/zmeventnotification/issues/37)
- Auth problem [\#36](https://github.com/pliablepixels/zmeventnotification/issues/36)
- Very nice addition to my Docker [\#35](https://github.com/pliablepixels/zmeventnotification/issues/35)
- PTZ issues ... was working but doesn't seem to be now. [\#34](https://github.com/pliablepixels/zmeventnotification/issues/34)
- Cannot get secure connections to work in iOS 11.1.2 [\#33](https://github.com/pliablepixels/zmeventnotification/issues/33)
- cannot get zmNinja to connect [\#32](https://github.com/pliablepixels/zmeventnotification/issues/32)
- zmeventserver won't start after logInit\(\); [\#31](https://github.com/pliablepixels/zmeventnotification/issues/31)
- Relook at active connections in case multiple ones have the same token [\#30](https://github.com/pliablepixels/zmeventnotification/issues/30)
- Does this need zoneminder authentication turned on? [\#27](https://github.com/pliablepixels/zmeventnotification/issues/27)
- zmeventnotification that doesn't catch almost all the new events in Mocord [\#25](https://github.com/pliablepixels/zmeventnotification/issues/25)
- Unable to start zmeventnotification.pl [\#23](https://github.com/pliablepixels/zmeventnotification/issues/23)
- Discoverability for auto-conf? [\#22](https://github.com/pliablepixels/zmeventnotification/issues/22)
- Unable to connect to server [\#19](https://github.com/pliablepixels/zmeventnotification/issues/19)
- syntax error: newline unexpected [\#18](https://github.com/pliablepixels/zmeventnotification/issues/18)
- zmeventnotification.pl runs from command-line but not via zmdc.pl/zmpkg.pl [\#17](https://github.com/pliablepixels/zmeventnotification/issues/17)
- zmeventserver email event [\#16](https://github.com/pliablepixels/zmeventnotification/issues/16)
- Install on Centos 6.x [\#15](https://github.com/pliablepixels/zmeventnotification/issues/15)
- Integration with belkin wemo [\#14](https://github.com/pliablepixels/zmeventnotification/issues/14)
- ZMEventServer running but no events being received by client [\#13](https://github.com/pliablepixels/zmeventnotification/issues/13)
- daft question [\#12](https://github.com/pliablepixels/zmeventnotification/issues/12)
- Can't Start Eventnotification [\#10](https://github.com/pliablepixels/zmeventnotification/issues/10)
- Settting up Real Time Alerts/Notifications with ZMninja [\#9](https://github.com/pliablepixels/zmeventnotification/issues/9)
- zmeventnotification exits after INF \[About to start listening to socket\] when run with zmdc [\#8](https://github.com/pliablepixels/zmeventnotification/issues/8)
- Net::WebSocket::Server missing [\#7](https://github.com/pliablepixels/zmeventnotification/issues/7)
- Push Issue [\#5](https://github.com/pliablepixels/zmeventnotification/issues/5)
- test [\#4](https://github.com/pliablepixels/zmeventnotification/issues/4)
- Update to use reliable push service [\#3](https://github.com/pliablepixels/zmeventnotification/issues/3)
- After waiting for the interval specified the first time, notifications don't seem to honor the time interval [\#2](https://github.com/pliablepixels/zmeventnotification/issues/2)
- malformed json can crash the server [\#1](https://github.com/pliablepixels/zmeventnotification/issues/1)

**Merged pull requests:**

- add secret support [\#168](https://github.com/pliablepixels/zmeventnotification/pull/168) ([pliablepixels](https://github.com/pliablepixels))
- Fix formatting of code block on Hooks guide page [\#166](https://github.com/pliablepixels/zmeventnotification/pull/166) ([davidjb](https://github.com/davidjb))
- Fixing MQTT Insecure connection [\#146](https://github.com/pliablepixels/zmeventnotification/pull/146) ([artistan82](https://github.com/artistan82))
- proper pip3 version import [\#144](https://github.com/pliablepixels/zmeventnotification/pull/144) ([ratmole](https://github.com/ratmole))
- 140 improve match past detections feature [\#142](https://github.com/pliablepixels/zmeventnotification/pull/142) ([neillbell](https://github.com/neillbell))
- docs: Fix install.sh command line [\#139](https://github.com/pliablepixels/zmeventnotification/pull/139) ([mnoorenberghe](https://github.com/mnoorenberghe))
- migrate to pyzm logger [\#136](https://github.com/pliablepixels/zmeventnotification/pull/136) ([pliablepixels](https://github.com/pliablepixels))
- updates to for auth and updated mosquitto version 3.1.1 [\#135](https://github.com/pliablepixels/zmeventnotification/pull/135) ([vajonam](https://github.com/vajonam))
- OpenALPR support [\#132](https://github.com/pliablepixels/zmeventnotification/pull/132) ([pliablepixels](https://github.com/pliablepixels))
- alpr initial integration [\#129](https://github.com/pliablepixels/zmeventnotification/pull/129) ([pliablepixels](https://github.com/pliablepixels))
- Add a note about MQTT compatibility and a work around [\#126](https://github.com/pliablepixels/zmeventnotification/pull/126) ([gerdesj](https://github.com/gerdesj))
- Ignore objects matched in previous alarm  [\#120](https://github.com/pliablepixels/zmeventnotification/pull/120) ([pliablepixels](https://github.com/pliablepixels))
- support for bcrypt [\#116](https://github.com/pliablepixels/zmeventnotification/pull/116) ([pliablepixels](https://github.com/pliablepixels))
- clean logs, also clear hook text when it is updated [\#115](https://github.com/pliablepixels/zmeventnotification/pull/115) ([pliablepixels](https://github.com/pliablepixels))
- forgotten space [\#113](https://github.com/pliablepixels/zmeventnotification/pull/113) ([cmintey](https://github.com/cmintey))
- WEB\_OWNER and WEB\_GROUP defaults from environment [\#111](https://github.com/pliablepixels/zmeventnotification/pull/111) ([irremotus](https://github.com/irremotus))
- Rework detection flow to make model priority apply across files [\#110](https://github.com/pliablepixels/zmeventnotification/pull/110) ([pliablepixels](https://github.com/pliablepixels))
- fix mislabeled picture\_url example in default config [\#108](https://github.com/pliablepixels/zmeventnotification/pull/108) ([joelsdc](https://github.com/joelsdc))
- Replaced two occurrences where the incorrect equivalence operator was being used [\#106](https://github.com/pliablepixels/zmeventnotification/pull/106) ([humblking](https://github.com/humblking))
- any config param can be overriden [\#102](https://github.com/pliablepixels/zmeventnotification/pull/102) ([pliablepixels](https://github.com/pliablepixels))



\* *This Changelog was automatically generated by [github_changelog_generator](https://github.com/github-changelog-generator/github-changelog-generator)*
