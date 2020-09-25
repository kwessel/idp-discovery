#!/bin/sh

setupPipe() {
    if [ -e $1 ]; then
        rm $1
    fi
    mkfifo -m 666 $1
}

# Make a "console" logging pipe that anyone can write too regardless of who owns the process.
setupPipe /tmp/logpipe
cat <> /tmp/logpipe &

setupPipe /var/log/apache2/access_log
(cat <> /var/log/apache2/access_log | awk -v ENV="$ENV" -v UT="$USERTOKEN" '{printf "httpd;access_log;%s;%s;%s\n", ENV, UT, $0; fflush()}' &>/tmp/logpipe) &

setupPipe /tmp/loghttpderror
(cat <> /tmp/loghttpderror  | awk -v ENV="$ENV" -v UT="$USERTOKEN" '{printf "httpd;error_log;%s;%s;%s\n", ENV, UT, $0; fflush()}' &>/tmp/logpipe) &

setupPipe /tmp/logwayf
(cat <> /tmp/logwayf | awk -v ENV="$ENV" -v UT="$USERTOKEN" '{printf "switchwayf;%s;%s;%s\n", ENV, UT, $0; fflush()}' &>/tmp/logpipe) &

