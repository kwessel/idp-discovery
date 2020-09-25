#!/bin/bash

if [ -f /etc/mda-$ENV.conf ]; then
    mv /etc/mda-$ENV.conf /etc/mda.conf
else
    echo No MDA configuration for environment "$ENV", nothing to do
    exit 1
fi

[ -z "$APACHE_LOCALHOST" ] && export APACHE_LOCALHOST=localhost
echo export APACHE_LOCALHOST=$APACHE_LOCALHOST >>/env.sh

/usr/local/bin/logging-init.sh
/usr/local/bin/wayf-update.sh > /tmp/logcron 2>&1 || exit 1
/sbin/crond -n
