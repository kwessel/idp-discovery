FROM centos
MAINTAINER techservices-iamu@illinois.edu <techservices-iamu@illinois.edu>

ARG MDA_VERSION=0.9.2
ARG MDA_FILENAME=aggregator-cli-$MDA_VERSION-bin.zip
ARG MDA_DIR=https://shibboleth.net/downloads/metadata-aggregator/$MDA_VERSION

RUN ln -fs /usr/share/zoneinfo/America/Chicago /etc/localtime \
    && yum install -y cronie unzip java-11-openjdk-headless openssl \
    && curl -o /tmp/$MDA_FILENAME $MDA_DIR/$MDA_FILENAME \
    && cd /opt \
    && unzip /tmp/$MDA_FILENAME \
    && rm /tmp/$MDA_FILENAME \
    && mv aggregator-cli-$MDA_VERSION mda \
    && yum remove -y unzip
COPY ./container_files/		/
CMD ["/docker-entrypoint.sh"]
