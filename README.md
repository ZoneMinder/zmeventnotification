What
----
The Event Notification Server sits along with ZoneMinder and offers real time notifications, support for push notifications as well as Machine Learning powered recognition.
As of today, it supports:
* detection of 80 types of objects (persons, cars, etc.) 
* face recognition
* deep license plate recognition

I will add more algorithms over time.

Documentation
-------------
- Documentation, including installation, FAQ etc.are [available here](https://zmeventnotification.readthedocs.io/en/latest/index.html)
- Always refer to the [Breaking Changes](https://zmeventnotification.readthedocs.io/en/latest/guides/breaking.html) document before you upgrade

Quickstart (Docker)
-------------------

### Using Docker hub

1. Start docker container

    ```
    docker run -d -t -p 1080:80 -p 9000:9000 \
        -e TZ='Europe/London' \
        -v /storage/docker/zoneminder/etc:/etc/zm \
        -v /storage/docker/zoneminder/events:/var/cache/zoneminder/events \
        -v /storage/docker/zoneminder/images:/var/cache/zoneminder/images \
        -v /storage/docker/zoneminder/mysql:/var/lib/mysql \
        -v /storage/docker/zoneminder/logs:/var/log/zm \
        --shm-size="512m" \
        --name zoneminder_ev \
        petergallagher/zmeventnotification
    ```

2. Configure `zmeventnotification.ini` in your local folder e.g. `/storage/docker/zoneminder/etc/zmeventnotification.ini`.
3. Configure SSL cert and key by placing them in your local config folder e.g. `/storage/docker/zoneminder/etc/`. When referencing them within `zmeventnotification.ini` be sure to use the Docker container paths e.g. `/etc/zm/zm.crt`.

### Local build

1. Build and tag container

    ```
    docker build -t zmeventnotification .
    ```

2. Start container

    ```
    docker run -d -t -p 1080:80 -p 9000:9000 \
        -e TZ='Europe/London' \
        -v /storage/docker/zoneminder/etc:/etc/zm \
        -v /storage/docker/zoneminder/events:/var/cache/zoneminder/events \
        -v /storage/docker/zoneminder/images:/var/cache/zoneminder/images \
        -v /storage/docker/zoneminder/mysql:/var/lib/mysql \
        -v /storage/docker/zoneminder/logs:/var/log/zm \
        --shm-size="512m" \
        --name zoneminder_ev \
        zmeventnotification
    ```

Screenshots
------------

Click each image for larger versions. Some of these images are from other users who have granted permission for use
###### (permissions received from: Rockedge/ZM Slack channel/Mar 15, 2019)

<img src="https://github.com/pliablepixels/zmeventnotification/blob/master/screenshots/person_face.jpg" width="300px" /> <img src="https://github.com/pliablepixels/zmeventnotification/blob/master/screenshots/delivery.jpg" width="300px" /> <img src="https://github.com/pliablepixels/zmeventnotification/blob/master/screenshots/car.jpg" width="300px" /> <img src="https://github.com/pliablepixels/zmeventnotification/blob/master/screenshots/alpr.jpg" width="300px" />
