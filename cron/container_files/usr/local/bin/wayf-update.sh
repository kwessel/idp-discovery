#!/bin/sh

. /env.sh

PIDFILE=/tmp/wayf-metadata.pid

# Vars for metadata aggregator
JAVA_HOME=/usr/lib/jvm/jre
JVMOPTS="-Xmx1024M"
export JAVA_HOME JVMOPTS

# Vars for conditional get of InCommon metadata
CGET_BASE=/opt/bash-library
LIB_DIR=$CGET_BASE/lib
CACHE_DIR=$CGET_BASE/cache
LOG_FILE=/dev/null
TMPDIR=/tmp
MDURL=http://md.incommon.org/InCommon/InCommon-metadata.xml
MDFile=/etc/metadata/incommon-metadata.xml
export LIB_DIR CACHE_DIR LOG_FILE TMPDIR

if [ -f "$PIDFILE" ]; then
    mainpid=`cat $PIDFILE`
    thisscript=`/bin/basename $0`
    mainpn=`ps -fp $mainpid |grep $thisscript`

    if [ "$mainpn" ]; then
	javapids=`pgrep java`

	for pid in $javapids; do
	    mdapn=`ps -fp $pid |grep /etc/mda.conf`

	    if [ "$mdapn" ]; then
		kill -9 $pid
	    fi
	done
    fi

    if [ -f "$PIDFILE" ]; then
	rm $PIDFILE
    fi
fi

echo $$ >$PIDFILE

echo `date` Starting WAYF metadata update

if [ ! -e $CACHE_DIR ]; then
    mkdir $CACHE_DIR
fi

$CGET_BASE/bin/cget.sh $MDURL >$TMPDIR/$$.xml.tmp
RET=$?
if [ $RET -eq 0 ]; then
    mv $TMPDIR/$$.xml.tmp $MDFile
else
    rm $TMPDIR/$$.xml.tmp
    echo `date` Conditional get of InCommon metadata failed with code $RET, using cached copy
fi

/opt/mda/mda.sh /etc/mda.conf main
RET=$?
if [ $RET -ne 0 ]; then
    echo `date` Metadata aggregator exited with code $RET, skipping metadata update
    rm $PIDFILE
    exit $RET
fi

rm $PIDFILE
echo `date` Finished WAYF metadata update
exit 0
