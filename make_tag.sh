#!/bin/bash
if [ -z "$1" ]; then
    echo "Getting version name from zm_detect.py"
    TAGVER=`python ./hook/zm_detect.py --bareversion`
else
	TAGVER=$1
fi
VER="${TAGVER/v/}"
echo "Creating tag:v$VER"

read -p "Please generate CHANGELOG and commit it BEFORE you tag. Press a key when ready..."
read -p "Press any key to create the tag or Ctrl-C to break..." -n1 
git tag -fa v$VER -m"v$VER"
git push -f --tags
