#!/bin/bash

#	Notes:  Auto deletion of events without objects detected in them is 
#	controlled by the auto_delete_noobject_events setting in /etc/zm/objectconfig.ini
#
#	Log file path is assumed to be in /var/log/zm (change LOGPATH if not)
#	It is assumed that you have not enabled OPT_AUTH for the ZM API.

# When invoked by zmeventnotification.pl it will be passed:
# $1 = eventId that triggered an alarm
# $2 = monitor ID of monitor that triggered an alarm
# $3 = monitor Name of monitor that triggered an alarm
# $4 = cause of alarm 
# $5 = storage path of event

# Make sure we return the cause back so its sent in the notification
echo "${4}"
#echo "$(date): POST EVENT FOR EID:${1} FOR MONITOR ${2} NAME ${3} CAUSE ${4} PATH ${5}" > /tmp/post_log.txt
#
if grep '^auto_delete_noobject_events=yes$' /etc/zm/objectconfig.ini
then
	LOGPATH="/var/log/zm/zmev_event_end.log"

	delete_event () {
		( echo -n "$(date) `basename $0`[$$] Delete Event Id ${1} \"${2}-${3}\" \"${4}\" " ;
		curl -s -XDELETE http://localhost/zm/api/events/${1}.json ;
		echo ) >> $LOGPATH 2>&1
	}

	case "${4}" in
		*detected:*) 
			# Event with Object detected. Do not delete it.
			;;
		*)
			if [ -f ${5}/objdetect.jpg ]
			then
				if [ -f ${5}/objects.json ] 
				then
					( echo -n "$(date) ${0}[$$] Not Deleting Event ${1} \"${2}-${3}\" \"${4}\" " ;
					echo "as it has object detected and was not an approximate match" ) >> $LOGPATH 2>&1
				else
					delete_event "$@"
				fi
			else
				delete_event "$@"
			fi
			;;
	esac
fi

exit 0
