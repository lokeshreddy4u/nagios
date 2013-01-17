#!/bin/sh

# Nagios plugin to report CPU usage on Linux boxes.

usage() {
# This function is called when a user enters impossible values.
echo "Usage: $0 -H HOSTADDRESS [-C COMMUNITY] [-w WARNING] [-c CRITICAL] [-v VERSION]"
echo
echo " -H HOSTADDRESS"
echo "     The host to check, either IP address or a resolvable hostname."
echo " -w WARNING"
echo "     The percentage of cpu-idle to start warning, defaults to 15."
echo " -c CRITICAL"
echo "     The percentage op cpu-idle to reflect a critical state, defaults to 5."
echo " -C COMMUNITY"
echo "     The SNMP community to use, defaults to public."
echo " -v VERSION"
echo "     The SNMTP version to use, defaults to 2c."
exit 3
}

readargs() {
# This function reads what options and arguments were given on the
# command line.
while [ "$#" -gt 0 ] ; do
  case "$1" in
   -H)
    if [ "$2" ] ; then
     host="$2"
     shift ; shift
    else
     echo "Missing a value for $1."
     echo
     shift
     usage
    fi
   ;;
   -w)
    if [ "$2" ] ; then
     warning="$2"
     shift ; shift
    else
     echo "Missing a value for $1."
     echo
     shift
     usage
    fi
   ;;
   -c)
    if [ "$2" ] ; then
     critical="$2"
     shift ; shift
    else
     echo "Missing a value for $1."
     echo
     shift
     usage
    fi
   ;;
   -C)
    if [ "$2" ] ; then
     community="$2"
     shift ; shift
    else
     echo "Missing a value for $1."
     echo
     shift
     usage
    fi
   ;;
   -v)
    if [ "$2" ] ; then
     version="$2"
     shift ; shift
    else
     echo "Missing a value for $1."
     echo
     shift
     usage
    fi
   ;;
   *)
    echo "Unknown option $1."
    echo
    shift
    usage
   ;;
  esac
done
}

setvariables() {
# Here is a function to set some default values.
cpurawidle="UCD-SNMP-MIB::ssCpuRawIdle.0"
cpurawuser="UCD-SNMP-MIB::ssCpuRawUser.0"
cpurawsystem="UCD-SNMP-MIB::ssCpuRawSystem.0"
if [ ! "$warning" ] ; then warning="15" ; fi
if [ ! "$critical" ] ; then critical="5" ; fi
tmpdir="/tmp/nagios"
}

checkvariables() {
# This function checks if all collected input is correct.
if [ ! "$host" ] ; then
  echo "Please specify a hostname or IP address."
  echo
  usage
fi
if [ "$warning" -lt "$critical" ] ; then
  echo "Critical may not be higher than warning. Please modify your critical an warning values."
  echo
  usage
fi
if [ ! "$community" ] ; then
  # The public community is used when a user did not enter a community.
  community="public"
fi
if [ ! "$version" ] ; then
  # Version 2c is used when a user did not enter a version.
  version="2c"
fi
if [ ! -d "$tmpdir" ] ; then
  mkdir "$tmpdir"
  if [ $? -gt 0 ] ; then
   echo "Unknown cannot create $tmpdir!"
   exit 3
  fi
fi
}

getandprintresults() {
# First, get all values in one snmpget session. I think this is lighter for
# the machine that is queried compared to three separated snmpgets.
snmpget -c "$community" -v "$version" -t 3 "$host" "$cpurawidle" "$cpurawuser" "$cpurawsystem" | while read mib equals type digit ; do
case "$mib" in
  # This output is returned for the cpuidle value.
  UCD-SNMP-MIB::ssCpuRawIdle.0)
   cpuidlevalue="$digit"
  ;;
  # This output is returned for the cpuuser value.
  UCD-SNMP-MIB::ssCpuRawUser.0)
   cpuuservalue="$digit"
  ;;
  # This output is returned for the cpusystem value.
  UCD-SNMP-MIB::ssCpuRawSystem.0)
   cpusystemvalue="$digit"

   if [ -f "$tmpdir"/"$host".cpuidle ] ; then
    cpuidlediff=$(($cpuidlevalue - $(cat "$tmpdir"/"$host".cpuidle)))
   fi
   echo "$cpuidlevalue" > "$tmpdir"/"$host".cpuidle

   if [ -f "$tmpdir"/"$host".cpuuser ] ; then
    cpuuserdiff=$(($cpuuservalue - $(cat "$tmpdir"/"$host".cpuuser)))
   fi
   echo "$cpuuservalue" > "$tmpdir"/"$host".cpuuser

   if [ ! -f "$tmpdir"/"$host".cpusystem ] ; then
    echo "$cpusystemvalue" > "$tmpdir"/"$host".cpusystem
    echo "First run, gathering data."
    exit 3
   else
    cpusystemdiff=$(($cpusystemvalue - $(cat "$tmpdir"/"$host".cpusystem)))
    echo "$cpusystemvalue" > "$tmpdir"/"$host".cpusystem
   fi

   # Add all differences, so a calculation of the percentage can be made later.
   allcpu=$(($cpuidlediff + $cpuuserdiff + $cpusystemdiff))

   # Now calculate how many percent each value represents.
   cpuidlevalue=$((($cpuidlediff*100)/$allcpu))
   cpuuservalue=$((($cpuuserdiff*100)/$allcpu))
   cpusystemvalue=$((($cpusystemdiff*100)/$allcpu))

   # Now see if any of these percentages is over a threshold.
   if [ "$cpuidlevalue" -lt "$critical" ] ; then
    # First see if it's in a critical state.
    echo "CPU CRITICAL idle value: $cpuidlevalue%|cpuidle=$cpuidlevalue% cpuuservalue=$cpuuservalue% cpusystemvalue=$cpusystemvalue%"
    exit 2
   elif [ "$cpuidlevalue" -lt "$warning" ] ; then
    # Now see if warning applies.
    echo "CPU WARNING idle value: $cpuidlevalue%|cpuidle=$cpuidlevalue% cpuuservalue=$cpuuservalue% cpusystemvalue=$cpusystemvalue%"
    exit 1
   else
    # If neither critical, nor warning apply, it must be OK!
    echo "CPU OK idle value: $cpuidlevalue%|cpuidle=$cpuidlevalue% cpuuservalue=$cpuuservalue% cpusystemvalue=$cpusystemvalue%"
    exit 0
   fi
  ;;
  esac
done
}

# The calls to the different functions.
readargs "$@"
setvariables
checkvariables
getandprintresults
