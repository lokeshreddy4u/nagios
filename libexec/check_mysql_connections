#!/bin/bash
# 
# Script to monitor the open connections to a mysql server
# (C) 2006 Riege Software International GmbH
# Author: Gunther Schlegel <schlegel@riege.com>
# Published under the General Public License Version 2
# 
# Installation instructions:
# 1. Copy the script to you nagios plugins folder
# 2. Set executable rights
# 3. Send me a patch if you need to specify host, port, username or password
#
# V1.0.0  gs	20060817	new script
# V1.1.0  gs	20060818 	user mysqladmin options
# V1.1.1  gs	20070405	fix result calculation
#				fix by and thanks to Stephan Helas

source utils.sh

WARN=0
CRIT=0
USER=''
PASSWORD=''
HOST=''
PORT=''
MAXCONNS=0

usage() {
	echo "Script to monitor the number of concurrent connections"
	echo "to the mysql daemon"
	echo "Usage:"
	echo "$0 -w <WARNING PERCENT> -c <CRITICAL PERCENT> [-u username] [-p password] [-H hostname] [-P port]"
	exit $STATE_UNKNOWN
}

while getopts ":w:c:u:p:H:P:" opt; do
	case $opt in
		w ) 	WARN=$OPTARG ;;
		c ) 	CRIT=$OPTARG ;;
		u ) 	USER="--user=$OPTARG" ;;
		p ) 	PASSWORD="--password=$OPTARG" ;;
		H )	HOST="--host=$OPTARG" ;;
		P )	PORT="--port $OPTARG" ;;
		\?|h )	usage
			exit $STATE_UNKNOWN
	esac
done

if [ ! `which mysqladmin 2>/dev/null` ]; then
	echo "UNKNOWN: mysqladmin program not found."
	exit $STATE_UNKNOWN
fi

MYSQLOPTS="$USER $PASSWORD $HOST $PORT"

WARN=`echo $WARN|sed -e 's/%//g'`
CRIT=`echo $CRIT|sed -e 's/%//g'`

if [ $WARN -eq 0 -o $CRIT -eq 0 ]; then 
	echo "Parameter mismatch. Warning and crtical tesholds"
	echo "must not be 0."
	echo
	usage
elif [ $WARN -ge $CRIT ]; then
	echo "Critical treshold must not be smaller than warning treshold."
	echo 
	usage
elif [  -n "$PORT" -a -z "$HOST" ]; then
	echo "Port cannot be specified without host"
	echo 
	usage
fi


MAXCONNS=`mysqladmin $MYSQLOPTS variables 2>/dev/null|grep max_connections|cut -d '|' -f 3|sed -e 's/ //g'`
if [ "$MAXCONNS" = "0" -o "$MAXCONNS" = "" ]; then
	echo "UNKNOWN: cannot determine configured connection maximum."
	exit $STATE_UNKNOWN
fi

WARN=$((${MAXCONNS}*${WARN}/100))
CRIT=$((${MAXCONNS}*${CRIT}/100))

CONNS=$((`mysqladmin $MYSQLOPTS processlist 2>/dev/null|wc -l`-4))

if [ $CONNS -ge $CRIT ]; then
	echo "CRITICAL: $CONNS/$MAXCONNS mysql connections"
	exit $STATE_CRITICAL
elif [ $CONNS -ge $WARN ]; then
	echo "WARNING: $CONNS/$MAXCONNS mysql connections"
	exit $STATE_WARNING
elif [ $CONNS -ge 0 ]; then
	echo "OK: $CONNS/$MAXCONNS mysql connections"
	exit $STATE_OK
else
	echo "UNKNOWN: Cannot determine number of connections"
	exit $STATE_UNKNOWN
fi
