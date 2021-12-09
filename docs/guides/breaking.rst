Breaking Changes
----------------
'neo-ZMES' is starting out at version 0.0.1
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
- ZMES is now configured using YAML syntax/structure (zmeventnotification.yml and secrets.yml are for the ES, objectconfig and zm_secrets are for the object detection hooks).
- !SECRETS are now {[SECRETS]} - This allows for embedding in substrings and nested data structures.
- Absolutely not compatible with the source repos!
- ZMEventnotification.pl has been modified to add a --live flag when running the hooks python script zm_detect.py.
- ZMEventnotification.pl has been modified to accept a --docker command line option, this is to better support docker.
