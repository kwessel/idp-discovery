FROM spgreen/switch-wayf:2.0
MAINTAINER techservices-iamu@illinois.edu <techservices-iamu@illinois.edu>

RUN ln -fs /usr/share/zoneinfo/America/Chicago /etc/localtime \
    && apt -y update \
    && apt -y upgrade \
    && rm /opt/wayf/etc/IDProvider.conf.php /opt/wayf/etc/IDProvider.conf.dist.php /opt/wayf/etc/IDProvider.metadata.php
COPY ./container_files/		/
HEALTHCHECK CMD curl -k -f \
    'http://127.0.0.1/discovery/DS?entityID=urn:mace:incommon:uiuc.edu:healthcheck:container&return=https%3A%2F%2Fshibboleth.illinois.edu' \
    || exit 1
cmd ["/docker-entrypoint.sh"]
