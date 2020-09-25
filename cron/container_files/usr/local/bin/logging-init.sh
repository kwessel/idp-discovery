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

setupPipe /tmp/logcron
(cat <> /tmp/logcron  | awk -v ENV="$ENV" -v UT="$USERTOKEN" '{printf "cron;wayf-update;%s;%s;%s\n", ENV, UT, $0; fflush()}' &>/tmp/logpipe) &

