# Changelog

## [v6.1.0](https://github.com/pliablepixels/zmeventnotification/tree/v6.1.0) (2021-01-02)

[Full Changelog](https://github.com/pliablepixels/zmeventnotification/compare/v6.0.6...v6.1.0)

**Implemented enhancements:**

- Constant detection mode - \(ML\) [\#313](https://github.com/pliablepixels/zmeventnotification/issues/313)

**Closed issues:**

- zm\_detect.py Unrecoverable error: Already locked [\#351](https://github.com/pliablepixels/zmeventnotification/issues/351)
- Possible to have more than 2 frames analysis for objects detection [\#348](https://github.com/pliablepixels/zmeventnotification/issues/348)
- No face detection or recognition [\#347](https://github.com/pliablepixels/zmeventnotification/issues/347)
- Migrate to pycoral  looks like python3-edgetpu is now deprecated [\#346](https://github.com/pliablepixels/zmeventnotification/issues/346)
- Error in zm\_detect.py with assertion lock on es 6.0+? [\#344](https://github.com/pliablepixels/zmeventnotification/issues/344)
- Is there a way to get phone notifications for person events only? [\#343](https://github.com/pliablepixels/zmeventnotification/issues/343)
- Only recieve one notification per/recording. [\#342](https://github.com/pliablepixels/zmeventnotification/issues/342)
- freebsd... [\#339](https://github.com/pliablepixels/zmeventnotification/issues/339)
- push notification min interval still not working [\#336](https://github.com/pliablepixels/zmeventnotification/issues/336)
- \(Suggestion/Question\) Multiple object detection sources [\#335](https://github.com/pliablepixels/zmeventnotification/issues/335)
- multizone, different detection\_sequence [\#334](https://github.com/pliablepixels/zmeventnotification/issues/334)
- Discrepancy between local and remote hook processing [\#333](https://github.com/pliablepixels/zmeventnotification/issues/333)

**Merged pull requests:**

- Unintentional nohup? [\#340](https://github.com/pliablepixels/zmeventnotification/pull/340) ([otkd](https://github.com/otkd))
- Fix two typos in docs/guides/hooks.rst [\#338](https://github.com/pliablepixels/zmeventnotification/pull/338) ([adamjernst](https://github.com/adamjernst))

## [v6.0.6](https://github.com/pliablepixels/zmeventnotification/tree/v6.0.6) (2020-10-27)

[Full Changelog](https://github.com/pliablepixels/zmeventnotification/compare/v6.0.5...v6.0.6)

**Implemented enhancements:**

- multizone, different object\_detection\_pattern [\#319](https://github.com/pliablepixels/zmeventnotification/issues/319)

**Closed issues:**

- objdetect\_mp4 doesnt show detected object polygons [\#332](https://github.com/pliablepixels/zmeventnotification/issues/332)
- Getting erroneous push notifications \(still\) [\#331](https://github.com/pliablepixels/zmeventnotification/issues/331)
- Configured image path not recognized [\#330](https://github.com/pliablepixels/zmeventnotification/issues/330)
- fcmv1: FCM push message Error:400 Bad Request [\#329](https://github.com/pliablepixels/zmeventnotification/issues/329)

## [v6.0.5](https://github.com/pliablepixels/zmeventnotification/tree/v6.0.5) (2020-10-22)

[Full Changelog](https://github.com/pliablepixels/zmeventnotification/compare/v6.0.4...v6.0.5)

**Implemented enhancements:**

- Allow option to replace notifications on system tray/notification bar [\#322](https://github.com/pliablepixels/zmeventnotification/issues/322)

**Fixed bugs:**

- 1.6.000: Getting notifications for monitors that have "report events" unchecked  [\#321](https://github.com/pliablepixels/zmeventnotification/issues/321)
- objectconfig.ini version number not updated in example config  [\#318](https://github.com/pliablepixels/zmeventnotification/issues/318)
- Push notification minimum timer does not work. [\#320](https://github.com/pliablepixels/zmeventnotification/issues/320)

**Closed issues:**

- More of question than issue - multi server install - event  [\#323](https://github.com/pliablepixels/zmeventnotification/issues/323)
- Migrated objectdetection.ini not picking up polygons? [\#315](https://github.com/pliablepixels/zmeventnotification/issues/315)

## [v6.0.4](https://github.com/pliablepixels/zmeventnotification/tree/v6.0.4) (2020-10-17)

[Full Changelog](https://github.com/pliablepixels/zmeventnotification/compare/v6.0.2...v6.0.4)

**Fixed bugs:**

- FCMv1: FCM push message Error:500 Internal Server Error [\#314](https://github.com/pliablepixels/zmeventnotification/issues/314)
- trailing spaces are not trimmed when reading from zmeventnotification.ini [\#311](https://github.com/pliablepixels/zmeventnotification/issues/311)

**Closed issues:**

- No longer receiving image in notification on Android [\#312](https://github.com/pliablepixels/zmeventnotification/issues/312)

## [v6.0.2](https://github.com/pliablepixels/zmeventnotification/tree/v6.0.2) (2020-10-14)

[Full Changelog](https://github.com/pliablepixels/zmeventnotification/compare/v6.0.1...v6.0.2)

**Closed issues:**

- Minor maintenance fixes [\#310](https://github.com/pliablepixels/zmeventnotification/issues/310)

## [v6.0.1](https://github.com/pliablepixels/zmeventnotification/tree/v6.0.1) (2020-10-14)

[Full Changelog](https://github.com/pliablepixels/zmeventnotification/compare/v5.15.6...v6.0.1)

**Implemented enhancements:**

- support FCM v1 protocol [\#307](https://github.com/pliablepixels/zmeventnotification/issues/307)
- Migrate from Legacy FCM to HTTP v1 for better features [\#306](https://github.com/pliablepixels/zmeventnotification/issues/306)
- migrate tokens to a JSON format [\#305](https://github.com/pliablepixels/zmeventnotification/issues/305)
- Start building out a configurable notification json rule file [\#298](https://github.com/pliablepixels/zmeventnotification/issues/298)
- poly line thickness setting \(0=off\) [\#291](https://github.com/pliablepixels/zmeventnotification/issues/291)
- Feature Request: Include support for Google Coral USB Accelerator [\#283](https://github.com/pliablepixels/zmeventnotification/issues/283)
- zmes install without local models \(for remote detection\) [\#267](https://github.com/pliablepixels/zmeventnotification/issues/267)
- Possibility to have zmeventnotification triggered on existing events \(batch processing vs realtime\) [\#265](https://github.com/pliablepixels/zmeventnotification/issues/265)
- ES needs to support tokens [\#185](https://github.com/pliablepixels/zmeventnotification/issues/185)
- Fast gif option [\#304](https://github.com/pliablepixels/zmeventnotification/pull/304) ([lucasnz](https://github.com/lucasnz))
- Add support for MQTT over TLS [\#285](https://github.com/pliablepixels/zmeventnotification/pull/285) ([nmeylan](https://github.com/nmeylan))

**Fixed bugs:**

- Logging to syslog despite LOG\_LEVEL\_SYSLOG setting [\#303](https://github.com/pliablepixels/zmeventnotification/issues/303)

**Closed issues:**

- Coral Edge TPU - HandleQueuedBulkIn transfer in failed. Not found: USB transfer error 5 \[LibUsbDataInCallback\] [\#302](https://github.com/pliablepixels/zmeventnotification/issues/302)
- Not saving unknown faces [\#299](https://github.com/pliablepixels/zmeventnotification/issues/299)
- Problem with object:person does not fall into any polygons [\#297](https://github.com/pliablepixels/zmeventnotification/issues/297)
- Possible to delete recordings with no detections? [\#296](https://github.com/pliablepixels/zmeventnotification/issues/296)
- Permission error when trying to train faces [\#295](https://github.com/pliablepixels/zmeventnotification/issues/295)
- Missed license plates due to incorrect polygon comparison [\#294](https://github.com/pliablepixels/zmeventnotification/issues/294)
- automatic license plate number lookup ? [\#292](https://github.com/pliablepixels/zmeventnotification/issues/292)
- Error after 5.16.0-upgrade.  [\#290](https://github.com/pliablepixels/zmeventnotification/issues/290)
- Notification Image showing on WAN, does not resolve on LAN and thus doesn't show image [\#288](https://github.com/pliablepixels/zmeventnotification/issues/288)
- How to improve initial detection? [\#287](https://github.com/pliablepixels/zmeventnotification/issues/287)
- \[For Comments\] Reworking ES objectconfig to make it more intuitive to add other models in future & concurrent execution limit [\#284](https://github.com/pliablepixels/zmeventnotification/issues/284)
- zm\_detect.py can't run - SyntaxError [\#282](https://github.com/pliablepixels/zmeventnotification/issues/282)
- Error parsing objectconfig.ini file [\#280](https://github.com/pliablepixels/zmeventnotification/issues/280)

**Merged pull requests:**

- fix a bug: Unrecoverable error:local variable 'pred' referenced befor… [\#309](https://github.com/pliablepixels/zmeventnotification/pull/309) ([lucasnz](https://github.com/lucasnz))
- Fix call to g.logger.Debug\(\) that was causing an TypeError exception. [\#301](https://github.com/pliablepixels/zmeventnotification/pull/301) ([neillbell](https://github.com/neillbell))
- correct object\_labels value for tinyyolo v3 / v4 [\#293](https://github.com/pliablepixels/zmeventnotification/pull/293) ([hugalafutro](https://github.com/hugalafutro))
- fix\(import\_zm\_zones\): remove findWholeWord\('All'\) condition from match\_reason [\#289](https://github.com/pliablepixels/zmeventnotification/pull/289) ([matthewtgilbride](https://github.com/matthewtgilbride))
- Dev [\#286](https://github.com/pliablepixels/zmeventnotification/pull/286) ([pliablepixels](https://github.com/pliablepixels))

## [v5.15.6](https://github.com/pliablepixels/zmeventnotification/tree/v5.15.6) (2020-06-30)

[Full Changelog](https://github.com/pliablepixels/zmeventnotification/compare/v5.15.5...v5.15.6)

**Closed issues:**

- Various breaking updates to 5.15.6 [\#281](https://github.com/pliablepixels/zmeventnotification/issues/281)
- Function process\_config\(\) not checking only\_triggered\_zm\_zones correctly [\#277](https://github.com/pliablepixels/zmeventnotification/issues/277)
- ZoneMinder zones are always imported regardless of the setting of import\_zm\_zones [\#275](https://github.com/pliablepixels/zmeventnotification/issues/275)

## [v5.15.5](https://github.com/pliablepixels/zmeventnotification/tree/v5.15.5) (2020-06-25)

[Full Changelog](https://github.com/pliablepixels/zmeventnotification/compare/v5.13.3...v5.15.5)

**Implemented enhancements:**

- Allow feature to limit object detection only to zones ZM detected motion in, at the time of reporting to ES [\#273](https://github.com/pliablepixels/zmeventnotification/issues/273)
- Create a placeholder for user invoked scripts that don't need messing with OD scripts [\#259](https://github.com/pliablepixels/zmeventnotification/issues/259)

**Fixed bugs:**

- Docs Issue: Making sure everything is running \(in manual mode\) [\#270](https://github.com/pliablepixels/zmeventnotification/issues/270)

**Closed issues:**

- No patterns found using any models in all files [\#274](https://github.com/pliablepixels/zmeventnotification/issues/274)
- question:  understanding alerts and object detection \(with import\_zones\) [\#271](https://github.com/pliablepixels/zmeventnotification/issues/271)
- question: skip\_monitors and hook\_skip\_monitors [\#269](https://github.com/pliablepixels/zmeventnotification/issues/269)
- Training faces [\#268](https://github.com/pliablepixels/zmeventnotification/issues/268)
- Fatal SQL Error [\#264](https://github.com/pliablepixels/zmeventnotification/issues/264)
- CSPR configuration  [\#258](https://github.com/pliablepixels/zmeventnotification/issues/258)
- Questions about detect pattern in zones and alpr known plates [\#256](https://github.com/pliablepixels/zmeventnotification/issues/256)
- Enhancement: don't tag items reported in previous alert [\#255](https://github.com/pliablepixels/zmeventnotification/issues/255)
- Problem with own push\_api script [\#254](https://github.com/pliablepixels/zmeventnotification/issues/254)
- Error downloading files: unknown url type [\#252](https://github.com/pliablepixels/zmeventnotification/issues/252)
- Getting Constant Notifications - "Last Time Not Found" [\#248](https://github.com/pliablepixels/zmeventnotification/issues/248)

**Merged pull requests:**

- Update query parameters in utils.py to fix authentication failure [\#279](https://github.com/pliablepixels/zmeventnotification/pull/279) ([cornercase](https://github.com/cornercase))
- Modify process\_config\(\) to properly check only\_triggered\_zm\_zones for… [\#278](https://github.com/pliablepixels/zmeventnotification/pull/278) ([neillbell](https://github.com/neillbell))
- Properly check the state of only\_triggered\_zm\_zones  [\#276](https://github.com/pliablepixels/zmeventnotification/pull/276) ([neillbell](https://github.com/neillbell))
- add a configuration option to set the topic for MQTT instead of the h… [\#272](https://github.com/pliablepixels/zmeventnotification/pull/272) ([dennyreiter](https://github.com/dennyreiter))
- ftp\_detect\_image.py contrib script [\#261](https://github.com/pliablepixels/zmeventnotification/pull/261) ([0n3man](https://github.com/0n3man))
- Update image\_manip.py [\#260](https://github.com/pliablepixels/zmeventnotification/pull/260) ([0n3man](https://github.com/0n3man))
- spelling fix [\#253](https://github.com/pliablepixels/zmeventnotification/pull/253) ([firefly2442](https://github.com/firefly2442))

## [v5.13.3](https://github.com/pliablepixels/zmeventnotification/tree/v5.13.3) (2020-04-27)

[Full Changelog](https://github.com/pliablepixels/zmeventnotification/compare/v5.11.3...v5.13.3)

**Implemented enhancements:**

- MQTT Retain option [\#246](https://github.com/pliablepixels/zmeventnotification/issues/246)

**Fixed bugs:**

- Error when using import\_zm\_zones=yes \(incorrect encoding of password\) [\#245](https://github.com/pliablepixels/zmeventnotification/issues/245)
- Event server sends FCS event\_end\_notification for not subscribed monitors [\#242](https://github.com/pliablepixels/zmeventnotification/issues/242)
- Sometimes there are duplicate entries in event notes. [\#238](https://github.com/pliablepixels/zmeventnotification/issues/238)
- /dev/shm 100% used, caused by ZMEventnotification? [\#210](https://github.com/pliablepixels/zmeventnotification/issues/210)

**Closed issues:**

- zmeventnotification.pl crash when i open zmninja [\#251](https://github.com/pliablepixels/zmeventnotification/issues/251)
- Error when running zm\_train\_faces.py \(KeyError: 'file'\) [\#250](https://github.com/pliablepixels/zmeventnotification/issues/250)
- Better images for notifications  [\#244](https://github.com/pliablepixels/zmeventnotification/issues/244)
- Feature suggestion: Support forced alarm trigger via MQTT [\#243](https://github.com/pliablepixels/zmeventnotification/issues/243)
- bad bcrypt settings at line 1473 [\#241](https://github.com/pliablepixels/zmeventnotification/issues/241)
- platerecognizer.com SDK call fails [\#236](https://github.com/pliablepixels/zmeventnotification/issues/236)

**Merged pull requests:**

- Update zmeventnotification.pl [\#249](https://github.com/pliablepixels/zmeventnotification/pull/249) ([makers-mark](https://github.com/makers-mark))
- add MQTT Retain flag option [\#247](https://github.com/pliablepixels/zmeventnotification/pull/247) ([darknicht66](https://github.com/darknicht66))

## [v5.11.3](https://github.com/pliablepixels/zmeventnotification/tree/v5.11.3) (2020-04-02)

[Full Changelog](https://github.com/pliablepixels/zmeventnotification/compare/v5.11.2...v5.11.3)

## [v5.11.2](https://github.com/pliablepixels/zmeventnotification/tree/v5.11.2) (2020-03-31)

[Full Changelog](https://github.com/pliablepixels/zmeventnotification/compare/v5.9.9...v5.11.2)

**Implemented enhancements:**

- Add ability to skip monitors in ES \(not just hooks\) [\#240](https://github.com/pliablepixels/zmeventnotification/issues/240)
- Add option for bestmatch priority  [\#237](https://github.com/pliablepixels/zmeventnotification/issues/237)
- Add live push notification support [\#235](https://github.com/pliablepixels/zmeventnotification/issues/235)

**Fixed bugs:**

- zm\_zones don't get imported if there is no monitor section in objectconfig.ini for the provided monitor id [\#230](https://github.com/pliablepixels/zmeventnotification/issues/230)

**Closed issues:**

- cant authenticate to MQTT broker [\#231](https://github.com/pliablepixels/zmeventnotification/issues/231)
- Events being missed. [\#229](https://github.com/pliablepixels/zmeventnotification/issues/229)
- Detected licence plates missing in notes [\#227](https://github.com/pliablepixels/zmeventnotification/issues/227)

**Merged pull requests:**

- Fix typo in version option handling [\#239](https://github.com/pliablepixels/zmeventnotification/pull/239) ([lpomfrey](https://github.com/lpomfrey))
- General skip monitors [\#234](https://github.com/pliablepixels/zmeventnotification/pull/234) ([connortechnology](https://github.com/connortechnology))
- small efficiency improvement [\#233](https://github.com/pliablepixels/zmeventnotification/pull/233) ([connortechnology](https://github.com/connortechnology))

## [v5.9.9](https://github.com/pliablepixels/zmeventnotification/tree/v5.9.9) (2020-03-08)

[Full Changelog](https://github.com/pliablepixels/zmeventnotification/compare/v5.7.7...v5.9.9)

**Implemented enhancements:**

- Add ability to add any arbitrary 3rd party push server [\#225](https://github.com/pliablepixels/zmeventnotification/issues/225)
- Add native component support to Home Assistant for ES events [\#141](https://github.com/pliablepixels/zmeventnotification/issues/141)

**Fixed bugs:**

- ZM may overwrite detection [\#224](https://github.com/pliablepixels/zmeventnotification/issues/224)

**Closed issues:**

- zm\_train\_faces.py fails [\#232](https://github.com/pliablepixels/zmeventnotification/issues/232)
- zmeventserver not connecting to mlapi after zm upgrade [\#228](https://github.com/pliablepixels/zmeventnotification/issues/228)
- Montage Review Calendars not updating [\#223](https://github.com/pliablepixels/zmeventnotification/issues/223)
- Can zmeventnotification.pl update Events.ObjectScore? [\#222](https://github.com/pliablepixels/zmeventnotification/issues/222)
- MQTT username and password not in secrets.ini  [\#220](https://github.com/pliablepixels/zmeventnotification/issues/220)
- Motion, Object Detection and linked cameras [\#208](https://github.com/pliablepixels/zmeventnotification/issues/208)
- No preview images on iOS and WatchOS when turning on ML Hooks [\#198](https://github.com/pliablepixels/zmeventnotification/issues/198)

**Merged pull requests:**

- Moves any MQTT username and password to secrets.ini [\#221](https://github.com/pliablepixels/zmeventnotification/pull/221) ([bmsleight](https://github.com/bmsleight))

## [v5.7.7](https://github.com/pliablepixels/zmeventnotification/tree/v5.7.7) (2020-02-20)

[Full Changelog](https://github.com/pliablepixels/zmeventnotification/compare/v5.7.4...v5.7.7)

**Implemented enhancements:**

- support OpenALPR local install \(via command line  binary\) [\#219](https://github.com/pliablepixels/zmeventnotification/issues/219)

**Closed issues:**

- Problem with zm\_detect.py [\#218](https://github.com/pliablepixels/zmeventnotification/issues/218)
- openALPR on own server [\#215](https://github.com/pliablepixels/zmeventnotification/issues/215)
- Using GPU in zm\_detect [\#213](https://github.com/pliablepixels/zmeventnotification/issues/213)

**Merged pull requests:**

- remove uneeded quotes. Convert " to ' where possible. [\#217](https://github.com/pliablepixels/zmeventnotification/pull/217) ([connortechnology](https://github.com/connortechnology))

## [v5.7.4](https://github.com/pliablepixels/zmeventnotification/tree/v5.7.4) (2020-02-12)

[Full Changelog](https://github.com/pliablepixels/zmeventnotification/compare/v5.4.1...v5.7.4)

**Implemented enhancements:**

- Add OpenCV 4.1.2 CUDA DNN support [\#214](https://github.com/pliablepixels/zmeventnotification/issues/214)
- API support for controlling ES behavior [\#211](https://github.com/pliablepixels/zmeventnotification/issues/211)
- Extend pyzm to pull event image & video files [\#207](https://github.com/pliablepixels/zmeventnotification/issues/207)
- Send JSON of detection along with string [\#206](https://github.com/pliablepixels/zmeventnotification/issues/206)
- Allow unknown faces to be saved so its easy to train on unknown faces [\#205](https://github.com/pliablepixels/zmeventnotification/issues/205)
- When using MLapi, fallback to local server on connection lost [\#204](https://github.com/pliablepixels/zmeventnotification/issues/204)
- Notifications on IOS show AM/PM instead of 24hrs as set in zmninja [\#202](https://github.com/pliablepixels/zmeventnotification/issues/202)

**Fixed bugs:**

- ZMeventnotification locks without error \(typically after several hours\) [\#175](https://github.com/pliablepixels/zmeventnotification/issues/175)

**Closed issues:**

- Failover to local if mlapi server is unavailable [\#212](https://github.com/pliablepixels/zmeventnotification/issues/212)
- Function is a reserved keyword in Mysql 8, resolve by quoting with backticks. [\#209](https://github.com/pliablepixels/zmeventnotification/issues/209)
- Enable ALPR only for one Monitor [\#203](https://github.com/pliablepixels/zmeventnotification/issues/203)
- iOS Notications does not show the type of object detected [\#201](https://github.com/pliablepixels/zmeventnotification/issues/201)
- OpenCV Object Tracking [\#197](https://github.com/pliablepixels/zmeventnotification/issues/197)
- Manual server start crashes [\#196](https://github.com/pliablepixels/zmeventnotification/issues/196)
- Explore ability to add "zone name" to MQTT payload - enhancment [\#195](https://github.com/pliablepixels/zmeventnotification/issues/195)
- Multiple zones in one camera, for diffrent objects [\#193](https://github.com/pliablepixels/zmeventnotification/issues/193)
- Segmentation fault and bad bcrypt settings at ./zmeventnotification.pl line 1061 [\#192](https://github.com/pliablepixels/zmeventnotification/issues/192)
- MQTT dropping event messages [\#191](https://github.com/pliablepixels/zmeventnotification/issues/191)
- MQTT/Home assistant support - maintainer needed [\#137](https://github.com/pliablepixels/zmeventnotification/issues/137)

**Merged pull requests:**

- Update config.rst [\#200](https://github.com/pliablepixels/zmeventnotification/pull/200) ([undigo](https://github.com/undigo))
- 191b mqtt publish from parent only [\#199](https://github.com/pliablepixels/zmeventnotification/pull/199) ([darknicht66](https://github.com/darknicht66))
- fixes \#191 add MQTT tick [\#194](https://github.com/pliablepixels/zmeventnotification/pull/194) ([darknicht66](https://github.com/darknicht66))

## [v5.4.1](https://github.com/pliablepixels/zmeventnotification/tree/v5.4.1) (2019-12-22)

[Full Changelog](https://github.com/pliablepixels/zmeventnotification/compare/v5.2.1...v5.4.1)

**Closed issues:**

- Clean up hook/no hook processing [\#190](https://github.com/pliablepixels/zmeventnotification/issues/190)
- Feature request Audio Processing [\#189](https://github.com/pliablepixels/zmeventnotification/issues/189)
- scikit-learn 0.21.3 =\> 0.22.0 depreciation warning and AttributeError [\#188](https://github.com/pliablepixels/zmeventnotification/issues/188)

## [v5.2.1](https://github.com/pliablepixels/zmeventnotification/tree/v5.2.1) (2019-12-21)

[Full Changelog](https://github.com/pliablepixels/zmeventnotification/compare/v5.1.2...v5.2.1)

**Fixed bugs:**

- notifications fail if there is no end\_hook even if OD succeeds [\#186](https://github.com/pliablepixels/zmeventnotification/issues/186)

**Closed issues:**

- \[PATCH\] FEATURE: Enhanced MQTT handling. [\#183](https://github.com/pliablepixels/zmeventnotification/issues/183)

## [v5.1.2](https://github.com/pliablepixels/zmeventnotification/tree/v5.1.2) (2019-12-20)

[Full Changelog](https://github.com/pliablepixels/zmeventnotification/compare/v5.0.1...v5.1.2)

## [v5.0.1](https://github.com/pliablepixels/zmeventnotification/tree/v5.0.1) (2019-12-19)

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
