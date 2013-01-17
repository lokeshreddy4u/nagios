#!/bin/bash

# Set some defaults
export THE_VERSION="1.0 beta 1"
export THE_USERNAME=Administrator
export THE_PASSWORD=password
export THE_HOSTNAME=localhost
export THE_PORT=8080
export SESSION_NAME=""
export WARNING_LEVEL=100
export CRITICAL_LEVEL=400
export NUMSESS=""

export OK_STATUSLEVEL=0
export OK_STATUSSTRING="OK"
export WARNING_STATUSLEVEL=1
export WARNING_STATUSSTRING="WARNING"
export CRITICAL_STATUSLEVEL=2
export CRITICAL_STATUSSTRING="CRITICAL"
export UNKNOWN_STATUSLEVEL=3
export UNKNOWN_STATUSSTRING="UNKNOWN"

export STATUSLEVEL=$OK_STATUSLEVEL
export STATUSSTRING="$OK_STATUSSTRING"

export WGET=`which wget`
if [ -z "$WGET" ]
then
	wget command not found. This plugin depends on it. Please install it and put it in path.
	exit 1
fi

export AWK=`which awk`
if [ -z "$WGET" ]
then
	awk command not found. This plugin depends on it. Please install it and put it in path.
	exit 1
fi

usage ()
{
	echo "Usage: `basename $0` [ -H hostname or IP address ] [ -P port ] [ -u username ] [ -p password ] [ -s session_name ] [ -w warning ] [ -c critical ]" >&2
	echo ""
	echo "If session_name is omitted (default) then the total number of sessions is calculated" >&2
	echo ""
	echo "DEFAULTS" >&2
	echo "hostname=localhost" >&2
	echo "port=8080" >&2
	echo "username=Administrator" >&2
	echo "password=password" >&2
	echo "session_name=""" >&2
	echo "warning=100" >&2
	echo "critical=400" >&2

	exit 1
}

version ()
{
	echo "`basename $0` $THE_VERSION"
}

# MAIN

while getopts ":u:p:H:P:s:w:c:hv" opt
do
	case "$opt" in
		u)
			THE_USERNAME="$OPTARG"
		;;
		p)
			THE_PASSWORD="$OPTARG"
		;;
		H)
			THE_HOSTNAME="$OPTARG"
		;;
		P)
			THE_PORT="$OPTARG"
		;;
		s)
			SESSION_NAME="$OPTARG"
		;;
		w)
			WARNING_LEVEL="$OPTARG"
		;;
		c)
			CRITICAL_LEVEL="$OPTARG"
		;;
		h)
			usage
			exit 1
		;;
		v)
			version
			exit 1
		;;
	esac
done


#NUMSESS=`$WGET -o /dev/null -O - "http://$THE_USERNAME:$THE_PASSWORD@$THE_HOSTNAME:$THE_PORT/manager/html" | $AWK -F ">|<" ' /row-center.*path.*'$SESSION_NAME'/ { SUM+=$7 } END { print SUM }'`
NUMSESS=`$WGET -o /dev/null -O - "http://$THE_USERNAME:$THE_PASSWORD@$THE_HOSTNAME:$THE_PORT/manager/list" | $AWK -F ":" ' /'$SESSION_NAME':/ { SUM+=$3 } END { print SUM }'`

if [ -z "$NUMSESS" -o "$?" -gt 0 ]
then
	STATUSLEVEL=$UNKNOWN_STATUSLEVEL
	STATUSSTRING="$UNKNOWN_STATUSSTRING"
fi
if [ $(( NUMSESS - WARNING_LEVEL )) -ge 0 ]
then
	STATUSLEVEL=$WARNING_STATUSLEVEL
	STATUSSTRING="$WARNING_STATUSSTRING"
	if [ $(( NUMSESS - CRITICAL_LEVEL )) -ge 0 ]
	then
		STATUSLEVEL=$CRITICAL_STATUSLEVEL
		STATUSSTRING="$CRITICAL_STATUSSTRING"
	fi
fi

echo "Tomcat sessions $SESSION_NAME $STATUSSTRING: $NUMSESS | sessions=$NUMSESS"

exit $STATUSLEVEL

