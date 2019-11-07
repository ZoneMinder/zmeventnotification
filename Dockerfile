FROM zoneminderhq/zoneminder:latest-ubuntu18.04
MAINTAINER Peter Gallagher

# Update base packages
RUN apt update \
    && apt upgrade --assume-yes

# Install pre-reqs
RUN apt install --assume-yes --no-install-recommends git wget \
        make gcc libyaml-perl libjson-perl libc6-dev \
        python3-dev python3-pip python3-setuptools 
RUN perl -MCPAN -e "install Crypt::MySQL" \
	&& perl -MCPAN -e "install Config::IniFiles" \
	&& perl -MCPAN -e "install Crypt::Eksblowfish::Bcrypt" \
	&& perl -MCPAN -e "install Net::WebSocket::Server" \
	&& perl -MCPAN -e "install LWP::Protocol::https" \
	&& perl -MCPAN -e "install Net::MQTT::Simple"
RUN pip3 install wheel

# Install zmeventnotification
RUN mkdir /opt/zmeventnotification
COPY . /opt/zmeventnotification/
RUN cd /opt/zmeventnotification \
	&& /opt/zmeventnotification/install.sh --no-interactive --install-es --install-hook --install-config

# Setup Volumes
VOLUME /var/lib/zoneminder/events /var/lib/zoneminder/images /var/lib/mysql /var/log/zm

# Expose ports
EXPOSE 80
EXPOSE 9000

# Configure entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
