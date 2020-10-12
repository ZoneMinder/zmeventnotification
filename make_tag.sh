#!/bin/bash
if [ -z "$1" ]; then
    echo "Inferring version name from hook/zmes_hook_helpers/__init__.py"
    if [[ `cat hook/zmes_hook_helpers/__init__.py` =~ ^__version__\ =\ \"(.*)\" ]];
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

read -p "Please generate CHANGELOG and commit it BEFORE you tag. Press a key when ready..."
read -p "Press any key to create the tag or Ctrl-C to break..." -n1 
git tag -fa v$VER -m"v$VER"
git push -f --tags
