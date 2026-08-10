#!/bin/bash

# ==============================================================================
# Description: Wrapper script for running the Perl file.
# Details    : - Ensures single-instance execution via a PID lock file (~/.<script_name>_pid).
#              - Cleans up stale PID files if a previous process died unexpectedly.
#              - Redirects execution and application logs to /home/userdir/log
#                with monthly log rotation based on YYYYMM format.
# ==============================================================================

MONTH=`date +%Y%m`
LOGPATH=/home/userdir/log
mkdir -p $LOGPATH

SN=`basename $0`
SCRIPTLOG=$LOGPATH/${SN}_script_$MONTH.log
APPLOG=$LOGPATH/${SN}_$MONTH.log
PID=$$
PIDFILE="/home/userdir/.${SN}_pid"

if [ -f $PIDFILE ]; then
  echo "" >> $SCRIPTLOG
  echo "==============" >> $SCRIPTLOG
  date >> $SCRIPTLOG
  echo "$PIDFILE exists" >> $SCRIPTLOG
  ps `cat $PIDFILE` | grep $0
  if [ $? -eq 0 ]; then # script already running
    echo "$0 is still running as process: `cat $PIDFILE`" >> $SCRIPTLOG
    exit
  else
    rm $PIDFILE >> $SCRIPTLOG
    echo "Removed stale PID file: $PIDFILE" >> $SCRIPTLOG
  fi
fi

(echo $PID > $PIDFILE) 2>> $SCRIPTLOG

cd <script_location>
echo "" >> $APPLOG
/bin/date >> $APPLOG
echo "" >> $APPLOG
perl perlfile.pl -cfg perl.cfg -o <option> >> $APPLOG 2>&1
