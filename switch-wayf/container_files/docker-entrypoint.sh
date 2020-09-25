#!/bin/bash

/usr/local/bin/logging-init.sh
/usr/local/bin/php /opt/wayf/bin/update-config.php >/dev/null && mv /opt/wayf/etc/config.new.php /opt/wayf/etc/config.php
/usr/local/bin/apache2-foreground
