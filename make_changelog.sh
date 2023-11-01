#!/bin/bash
if [ -z "$1" ]; then
    #echo "Getting version name from zm_detect.py"
    echo 'Getting version from zmeventnotification.pl'
    if [[ `cat ./zmeventnotification.pl` =~ my\ \$app_version\ =\ \'([0-9]*\.[0-9]*\.[0-9]*)\'\; ]];
    then
	    TAGVER=${BASH_REMATCH[1]}
    else
	    echo "Bad version parsing"
	    exit
    fi
else
	TAGVER=$1
fi
VER="${TAGVER/v/}"
read -p "Future release is v${VER}. Please press any key to confirm..."
github_changelog_generator -u zoneminder -p zmeventnotification --future-release v${VER}
#github_changelog_generator  --future-release v${VER}

