#!/bin/sh

# Version 1.2 as of 20-Jun-2012

# CONFIGURATION SECTION ################################################

# Note that since v1.2, these configs can be overridden by options

# nagiostats/icingastats/... executable
EXEC="/usr/local/nagios/bin/nagiostats"

# Cumulation function (MIN, MAX, AVG) and timeframe (1, 5, or 15
# minutes) of choice for the "gimme all there is" mode
CUMULATE="AVG"
TIMERANGE="5"

# Attempt to add the $TIMERANGEs used to the perfdata?
RANGETRACK=true

# Hostname and service description to use when passive check mode is
# requested and host and/or service cannot be determined
PASSIVE_EMERGENCY_HOST="Nagios"
PASSIVE_EMERGENCY_SERV="Nagios Stats"

########################################################################

PASSIVE=false
CONFIG=""

make_an_exit() {
   if $PASSIVE ; then
      date '+[%s] PROCESS_SERVICE_CHECK_RESULT;'"$PSV_HST;$PSV_SVC;$1;$2"
      exit 0
   else
      echo "$2"
      exit $1
   fi
}

while true ; do
   case $1 in
      # Controlling active/passive mode
      -p|--passive)
         PASSIVE=true
         PSV_HST="$2"
         PSV_SVC="$3"
         if [ "$PSV_HST" = "" -o "$PSV_SVC" = "" ]; then
            PSV_HST="$PASSIVE_EMERGENCY_HOST"
            PSV_SVC="$PASSIVE_EMERGENCY_SERV"
            make_an_exit 3 "UNKNOWN: `basename $0`: '--passive' needs to be followed by host ($2) and service ($3)"
         fi
         shift 2 ;;
      -a|--active)
         PASSIVE=false ;;
      # Options passed to $EXEC
      -c|--config|-s|--statsfile)
         CONFIG="$CONFIG $1 $2"
         shift ;;
      -c*|--config=*|-s*|--statsfile=*)
         CONFIG="$CONFIG $1" ;;
      # Modifying our own default configs
      -E|--exec|--EXEC)
         EXEC="$2"
         shift ;;
      -C|--cumulate|--CUMULATE)
         CUMULATE="$2"
         shift ;;
      -T|--timerange|--TIMERANGE)
         TIMERANGE="$2"
         shift ;;
      -R|--rangetrack|--RANGETRACK)
         RANGETRACK=true ;;
      -N|--norangetrack|--NORANGETRACK)
         RANGETRACK=false ;;
      # Online help
      -h|--help)
         BASESELF=`basename $0`
         BASEEXEC=`basename $EXEC`
         MODE="--active"
         if $PASSIVE ; then
            MODE="--passive '$PSV_HST' '$PSV_SVC'"
         fi
         TRACK="--NORANGETRACK"
         if $RANGETRACK ; then
            TRACK="--RANGETRACK"
         fi
         cat << EOHelp
Usage:		$BASESELF [ options ... ] [ checks ... ]
			Executes $BASEEXEC (or an equivalent command) to re-
			trieve internal statistics from your monitoring solu-
			tion, and optionally checks values against limits you
			specify.
			If no checks are requested, only values disagreeing
			from the preselected timerange and cumulation function
			are omitted from the output.
    Options:	--passive "Hostname" "Service Description"
			Output passive check result in external command syntax.
			(Remember to redirect the output to the command pipe.)
		--active
			Switches back to active check mode.
		--config Configfile
		--statsfile Statusfile
			Passed through as-is to $BASEEXEC (for OMD's benefit).
		--EXEC StatisticsGatherer	- i.e., /path/to/$BASEEXEC
		--CUMULATE CumulationFunction	- i.e., MIN, MAX, or AVG
		--TIMERANGE TimeRange		- i.e., 1, 5, or 15 (minutes)
		--RANGETRACK
		--NORANGETRACK
			Change $BASESELF configuration values on the fly.
		--help
			Output this help (and exit).
    Note:	The options and values set or implied at this point are:
			$MODE$CONFIG
			--EXEC $EXEC
			--CUMULATE $CUMULATE --TIMERANGE $TIMERANGE $TRACK
    Checks:	Every check is specified as:
			variable comparison value(pair)
		where:
			"variable" is any "MRTG variable" supported by your
				$BASEEXEC
			"comparison" is any numeric comparison operator that
				your local "test" executable offers
			"value(pair)" is either one integer (CRITICAL limit)
				or two integers with a '/' separator (i.e.,
				WARNING/CRITICAL)
			the result being TRUE means that the alert should be
				raised
			"variable -lt 0" can (should) be used to include the
				variable into the output without checking any
				limits on it
    Example:
	$BASESELF --active STATUSFILEAGETT -gt 900/1800 PROGRUNTIMETT -lt 0
	OK: STATUSFILEAGETT=3 PROGRUNTIMETT=160707 | STATUSFILEAGETT=3;900;1800 PROGRUNTIMETT=160707
		checks the age of your status.dat, returns WARNING/CRITICAL
		if the file hasn't been updated for more than 15/30 minutes,
		and also tells you how long the program has been running since
		the last restart/reload (without applying limits to that).
EOHelp
         exit 0 ;;
      # Unknown option
      -*)
         make_an_exit 3 "UNKNOWN: Unknown option '$1'" ;;
      # Not an option at all (parameters start)
      *)
         break ;;
   esac
   shift
done

if [ ! -x "$EXEC" ]; then
   make_an_exit 3 "UNKNOWN: Cannot find executable $EXEC"
fi

if [ $# -gt 0 ]; then
   EXITVAL=0
   EXITSTR="OK"
   OUTPUT=""
   while [ $# -gt 0 ]; do
      if [ "$1" = "" ]; then
         make_an_exit 3 "UNKNOWN: Need a value name"
      fi
      VALUE=`$EXEC $CONFIG -m -d "$1"`
      if [ "$VALUE" = "" -o "$VALUE" = "$1" ]; then
         make_an_exit 3 "UNKNOWN: Value $1 does not seem to exist"
      fi
      INTVAL="`echo $VALUE | sed -e 's/^\./0\./' -e 's/\..*//'`"
      if [ "`echo $INTVAL | sed -e 's/[0-9]*//'`" != "" ]; then
         make_an_exit 3 "UNKNOWN: Value $1 seems to be non-numeric ($VALUE)"
      fi
      if [ "`echo $3 | sed -e 's|.*/.*|/|'`" = "/" ]; then
         WARN="`echo $3 | sed -e 's|/.*||'`"
         CRIT="`echo $3 | sed -e 's|.*/||'`"
      else
         WARN=""
         CRIT="$3"
      fi
      if [ "$WARN" != "" -a "`echo $WARN | sed -e 's/[0-9]*//'`" != "" ]; then
         make_an_exit 3 "UNKNOWN: Not an integer: $WARN"
      fi
      if [ "$CRIT" = "" -o "`echo $CRIT | sed -e 's/[0-9]*//'`" != "" ]; then
         make_an_exit 3 "UNKNOWN: Not an integer: $CRIT"
      fi
      LIMITS=""
      for LIMIT in "$WARN" "$CRIT" ; do
         if [ "$LIMIT" = "" -o \( "$2" = "-lt" -a "$LIMIT" = "0" \) ]; then
            if [ "$CRIT" != "0" ]; then
               LIMITS="$LIMITS;"
            fi
         else
            case $2 in
               -eq) LIMITS="$LIMITS;@${LIMIT}:$LIMIT" ;;
               -ne) LIMITS="$LIMITS;${LIMIT}:$LIMIT" ;;
               -ge) LIMITS="$LIMITS;`echo $LIMIT 1 - p | dc`" ;;
               -gt) LIMITS="$LIMITS;$LIMIT" ;;
               -le) LIMITS="$LIMITS;`echo $LIMIT 1 + p | dc`:" ;;
               -lt) LIMITS="$LIMITS;${LIMIT}:" ;;
               *)   make_an_exit 3 "UNKNOWN: Not a comparison operator: $2" ;;
            esac
         fi
      done
      if [ $INTVAL $2 $CRIT ]; then
         EXITVAL=2
         EXITSTR="CRITICAL"
         OUTPUT="$OUTPUT "'**'"$1=$VALUE"'**'
      elif [ "$WARN" != "" ]; then
         if [ $INTVAL $2 $WARN ]; then
            if [ $EXITVAL -eq 0 ]; then
               EXITVAL=1
               EXITSTR="WARNING"
            fi
            OUTPUT="$OUTPUT "'*'"$1=$VALUE"'*'
         else
            OUTPUT="$OUTPUT $1=$VALUE"
         fi
      else
         OUTPUT="$OUTPUT $1=$VALUE"
      fi
      PERFDATA="$PERFDATA $1=$VALUE$LIMITS"
      if $RANGETRACK ; then
         if [ "`echo $1 | sed -e 's/[^0-9]//g'`" != "" ]; then
            PERFDATA="$PERFDATA r_$1=`echo $1 | sed -e 's/[^0-9][^0-9]*$//' -e 's/^.*[^0-9]//'`"
         fi
      fi
      shift 3
   done
   make_an_exit $EXITVAL "${EXITSTR}:$OUTPUT |$PERFDATA"
else
   PREFIX=""
   if $PASSIVE ; then
      PREFIX=`date '+[%s] PROCESS_SERVICE_CHECK_RESULT;'"$PSV_HST;$PSV_SVC;0;"`
   fi
   POSTFIX=""
   if $RANGETRACK ; then
      POSTFIX=" TimeRange=$TIMERANGE"
   fi
   $EXEC $CONFIG -m -d `$EXEC $CONFIG -h | egrep '^  *([A-Z][A-Z]|xx)' | \
      awk 'BEGIN { s=""; } { printf "%s%s=,%s",s,$1,$1; s=","; }' | \
      sed -e 's/xxxx*/'"$CUMULATE/g" -e 's/xx*/'"$TIMERANGE/g"` | \
      sed -e '/=$/N' -e 's/=[^0-9]*/=/' | egrep '=([0-9][0-9]*|[0-9]*\.[0-9][0-9]*)$' | \
      tr '\n' ' ' | sed -e 's/^/'"$PREFIX"'OK: Statistics read | /' -e 's/$/'"$POSTFIX/" | \
      grep 'OK: Statistics read'
   if [ $? -eq 0 ]; then
      exit 0
   else
      make_an_exit 2 "CRITICAL: Cannot read statistics with `basename $EXEC`"
   fi
fi

