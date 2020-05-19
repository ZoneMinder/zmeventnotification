Guidelines for contrib
=======================

The ``contrib/`` directory is for user provided scripts. These scripts could be for push, hooks or other things.

Scripts in ``contribs`` are NOT supported by me. Please don't ask me questions on why some of them don't work like you want them to. Reach out directly to the author. Which leads me to:

Contribution notes for developers
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If you are contributing a script, and want me to merge the PR into mainline, you need to follow these guidelines:

- Place your script inside the ``contrib/`` folder. ``install.sh`` will automatically take care of moving it. 

- Please put in proper comments on purpose/use.

- Make sure it is a general purpose script that is useful for others - if your script is fine tuned for a specific use-case that is not widely applicable, please don't create a PR. Keep it for your personal use.

- Please put in your github ID when doing PRs to contrib. It is expected that you support for script if there are questions. If you are not willing to do that, please don't create a PR (and if you do, I'm sorry, I can't accept it). What will then happen is if people post an issue about your script, they will either tag you, or I will. You are also free to point a link to a github issue tracker in your own ID if you want

- Use the right ES trigger to invoke your script. If your script does some housekeeping after object detection is done, ``event_xxx_hook_notify_userscript`` is probably the right trigger. If you are contributing a new push notification mechanism, ``api_push_script`` is the probably right trigger.

- Depending on which trigger you are using, take a look at the example scripts to see what arguments you get

