#!/bin/bash
if [ -z "$1" ]; then
    echo "Inferring version name from hooks/zm_ml/__init__.py"
    if [[ `cat hook/zm_ml/__init__.py` =~ ^__version__\ =\ \"(.*)\" ]];
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
github_changelog_generator -u pliablepixels -p zmeventnotification  --future-release v${VER}
#github_changelog_generator  --future-release v${VER}

