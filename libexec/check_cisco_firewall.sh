#!/bin/bash
#
# Written By: Pierre SOURDEAU to AMF company [FRANCE]
# Created: 28/10/2008
# Description: Check SNMP v 1, 2c, 3 for Cisco Firewall, and return :
### Mode 1 - Failover ###
# 	- fail over status for ptimary and secondary host
#		=> warning if primary = stanby and secondary = active
#		=> critical if primary or secondary = error
#		=> unknwon if failover is not configured
### Mode 2 - Sessions ###
# 	- number of sessions in use
#		=> warning or critical exit if superior
#	- number of max session ever used
#
# Each mode included graphic return to Centreon application
#
# Check succesfuly on Cisco PIX-515E and ASA-5500
#
# License: This nagios plugin comes with ABSOLUTELY NO WARRANTY. You may redistribute copies of
# the plugins under the terms of the GNU General Public License. For more information about these 
# matters, see the GNU General Public License.
# Version: 2.2 (updated 07/03/2009)

############################################################
# Varialbles
############################################################
usage="Usage: check_cisco_firewall.sh -H hostname -V version -M failover|sessions [-w|-c|-C|-l|-u|-a|-d|-h]
### PARAMETERS ### 
-H Hostname (IP adresse or DNS name)
-V Version (1|2c|3)
-M Mode (failover|sessions)
### OPTIONNAL ###
-w Warning_Level (number of sessions before warning) *** Use on session mode ***
-c Critical_Level (number of sessions before critical) *** Use on session mode ***
-C Community (name) *** Use on Version 1|2 ***
-l Login (NoAuthNoPriv | AuthNoPriv | AuthPriv) *** Use on Version 3 ***
-u Username *** Use on Version 3 ***
-a Password *** Use on Version 3 ***
-d Debug mode
-h Help (print command usage, and quit)"

result_value_Ok=0
result_value_Warning=1
result_value_Critical=2
result_value_Unknwon=3

sum_value_Ok=0
sum_value_Warning=0
sum_value_Critical=0
sum_value_Unknwon=0

failover_status_value=([3]=Down [4]=Error [9]=Active [10]=Standby)
actives_nodes=0
comm_final=""
walk_param=""


mib_failover_prim=".1.3.6.1.4.1.9.9.147.1.2.1.1.1.3.6"
mib_failover_sec=".1.3.6.1.4.1.9.9.147.1.2.1.1.1.3.7"
mib_sessions_current=".1.3.6.1.4.1.9.9.147.1.2.2.2.1.5.40.6"
mib_sessions_max=".1.3.6.1.4.1.9.9.147.1.2.2.2.1.5.40.7"


############################################################
# Global Functions
############################################################
# Check if value is numeric or not
check_num()
{
if ! let $1 2> /dev/null
then
	if [ $1 != 0 ]
	then
		echo "Error - Not numeric value : $2 = $1"
		exit $result_value_Unknwon
	fi
fi
}

# Check Parameters
check_param()
{
if [ "$hostname" == "" ] || [ "$version" == "" ] || [ "$mode" == "" ]
then
	echo "Error - Missing parameters - hostname = $hostname : version = $version : mode = $mode"
	echo "$usage"
	exit $result_value_Unknwon
fi

case $version in
		1 | 2c)
			if [ "$community" == "" ]
			then
				echo "Error - Missing parameters - community = $community"
				echo "$usage"
				exit $result_value_Unknwon
			fi
			walk_param="-v $version -c $community $hostname";;
		3) 
			if [ "$login" == "" ] || [ "$user" == "" ] || [ "$password" == "" ]
			then
				echo "Error - Missing parameters - login = $login : user = $user : password = $password"
				echo "$usage"
				exit $result_value_Unknwon
			fi
			walk_param="-v $version -l $login -u $user -A $password $hostname";;
esac
}


# Command used to debug
debug()
{
echo "*********************************************************************"
echo "### Mode Failover ###"
echo "Status primaire = $status_prim (${failover_status_value[$status_prim]})"
echo "Status secondaire = $status_sec (${failover_status_value[$status_sec]})"
echo "### Mode Sessions ###"
echo "Number of used sessions : $Used_Sessions"
echo "Number of max sessions ever used : $Max_Used_Sessions"
echo "### Global Values ###"
echo "Sum values : Ok = $sum_value_Ok ; Warning = $sum_value_Warning ; Critical = $sum_value_Critical ; Unknown = $sum_value_Unknwon"
echo "Nagios return : Ok = $result_value_Ok ; Warning = $result_value_Warning ; Critical = $result_value_Critical ; Unknown = $result_value_Unknwon"
echo "Parameters : Hostname = $hostname ; Version = $version ; Community = $community ; Mode = $mode ; warning = $warning ; critical = $critical ; login = $login ; user = $user ; password = $password"
echo "*********************************************************************"
}

# Results sent to Nagios
function_exit()
{
if [ $sum_value_Unknwon != 0 ]
then
	echo "Unknown $comm_final"
	exit $result_value_Unknwon
fi

if [ $sum_value_Critical != 0 ]
then
	echo "Critical $comm_final"
	exit $result_value_Critical
fi

if [ $sum_value_Warning != 0 ]
then
	echo "Warning $comm_final"
	exit $result_value_Warning
fi

if [ $sum_value_Ok != 0 ]
then
	echo "OK $comm_final"
	exit $result_value_Ok
fi

echo "Unknown - No result sent to nagios - End of script"
exit $result_value_Unknwon
}

############################################################
# Mode Failover Functions
############################################################
# Failover Status
failover_status()
{
	status_prim=`/usr/bin/snmpwalk $walk_param $mib_failover_prim | cut -d' ' -f4`
	check_num $status_prim status_prim
	status_sec=`/usr/bin/snmpwalk $walk_param $mib_failover_sec | cut -d' ' -f4`
	check_num $status_sec status_sec
}


# Failover Sum
failover_sum()
{
if [ $status_prim == 9 ] && [ $status_sec == 10 ]
then
	actives_nodes=2
	sum_value_Ok=$(( $sum_value_Ok + 1 ))
fi

if [ $status_prim == 10 ] && [ $status_sec == 9 ]
then
	actives_nodes=2
	sum_value_Warning=$(( $sum_value_Warning + 1 ))
fi

if [ $status_prim == 9 ] && [ $status_sec == 4 ]
then
	actives_nodes=1
	sum_value_Warning=$(( $sum_value_Warning + 1 ))
fi

if [ $status_prim == 4 ] && [ $status_sec == 9 ]
then
	actives_nodes=1
	sum_value_Critical=$(( $sum_value_Critical + 1 ))
fi

if [ $status_prim == 4 ] && [ $status_sec == 4 ]
then
	actives_nodes=0
	sum_value_Critical=$(( $sum_value_Critical + 1 ))
fi

if [ $status_prim == 3 ] && [ $status_sec == 3 ]
then
	actives_nodes=0
	sum_value_Unknwon=$(( $sum_value_Unknwon + 1 ))
fi

comm_final="$comm_final - Primary = ${failover_status_value[$status_prim]}, Secondary = ${failover_status_value[$status_sec]} | Actives_Nodes=$actives_nodes"
}


############################################################
# Mode Sessions Functions
############################################################
# The number of current sessions used
sessions_current()
{
	Used_Sessions=`/usr/bin/snmpwalk $walk_param $mib_sessions_current | cut -d' ' -f4`
	check_num $Used_Sessions Used_Sessions
}

# The number of max sessions ever used
sessions_max()
{
	if [ "$version" == "1" ]
	then
		Max_Used_Sessions=`/usr/bin/snmpwalk $walk_param $mib_sessions_max | cut -d' ' -f4 | sed -n '2p'`
	else
		Max_Used_Sessions=`/usr/bin/snmpwalk $walk_param $mib_sessions_max | cut -d' ' -f4`
	fi
	
	check_num $Max_Used_Sessions Max_Used_Sessions

	if [ $Used_Sessions -gt $Max_Used_Sessions ]
	then
		echo "Error - Too much sessions used : $Used_Sessions, but only $Max_Used_Sessions max sessions used !"
		exit $result_Unknwon
	fi
}

# Sessions Sum
sessions_sum()
{
if [ $Used_Sessions -lt $warning ]
then
	sum_value_Ok=$(( $sum_value_Ok + 1 ))
fi

if [ $Used_Sessions -ge $warning ] && [ $Used_Sessions -lt $critical ]
then
	sum_value_Warning=$(( $sum_value_Warning + 1 ))
fi

if [ $Used_Sessions -ge $critical ] || [ $Used_Sessions == 0 ]
then
	sum_value_Critical=$(( $sum_value_Critical + 1 ))
fi

comm_final="$comm_final - $Used_Sessions sessions (max : $Max_Used_Sessions) | Current_Used=$Used_Sessions"
}

############################################################
# Main Method
############################################################
# Get Options and check parameters
while getopts H:V:C:M:w:c:l:u:a:dh option;
do
	case $option in
		H) hostname=$OPTARG;;
		V) version=$OPTARG;;
		C) community=$OPTARG;;
		M) mode=$OPTARG;;
		w) warning=$OPTARG;;
		c) critical=$OPTARG;;
		l) login=$OPTARG;;
		u) user=$OPTARG;;
		a) password=$OPTARG;;
		d) debug=1;;
		h) echo "$usage"
		exit $result_Unknwon;;
	esac
done

check_param


### Mode 1 - Failover ### 
if [ "$mode" == "failover" ]
then
	# Functions lunch
	failover_status
	failover_sum
fi


### Mode 2 - Sessions ### 
if [ "$mode" == "sessions" ]
then
	# Parameters Checking
	check_num $warning warning
	check_num $critical critical

	# Functions lunch
	sessions_current
	sessions_max
	sessions_sum
fi


if [ "$debug" == 1 ]
then
	debug
fi

function_exit

