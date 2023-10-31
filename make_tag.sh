#!/bin/bash
if [ -z "$1" ]; then
    #echo "Getting version name from zm_detect.py"
    DETECT_TAGVER=`python3 ./hook/zm_detect.py --bareversion`
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
echo "(FYI: zm_detect version is ${DETECT_TAGVER})"
echo
read -p "Please generate CHANGELOG and commit it BEFORE you tag. Press a key when ready..."
read -p "Press any key to create the tag or Ctrl-C to break..." -n1 
echo "Modifying hook/zmes_hook_helpers/__init__.py to be ${DETECT_TAGVER}"
echo "__version__ = \"${DETECT_TAGVER}\"" > hook/zmes_hook_helpers/__init__.py 
echo "VERSION = __version__" >> hook/zmes_hook_helpers/__init__.py 

git tag -fa v$VER -m"v$VER"
git push -f --tags
git push upstream -f  --tags
