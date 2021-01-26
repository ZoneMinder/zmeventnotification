#!/bin/bash
if [ -z "$1" ]; then
    #echo "Getting version name from zm_detect.py"
    #TAGVER=`python ./hook/zm_detect.py --bareversion`
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
echo "Creating tag:v$VER"
echo "(FYI: zm_detect version is `python ./hook/zm_detect.py --bareversion`)"
echo
read -p "Please generate CHANGELOG and commit it BEFORE you tag. Press a key when ready..."
read -p "Press any key to create the tag or Ctrl-C to break..." -n1 
git tag -fa v$VER -m"v$VER"
git push -f --tags
