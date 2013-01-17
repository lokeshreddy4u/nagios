#!/bin/ksh
#------------------------------------------
#
# Created By : Jim DeNisco  
# File Name : check_cloud_health.ksh
# Creation Date : 02-08-2011
# Last Modified : Tue 08 Feb 2011 01:17:45 PM EST
# Category : Nagios Tools
# Purpose : Check cloud health
# Version : 0.9
#
#------------------------------------------


# running mysql query to get failed agents

test=`mysql -u nagios -pguest --host colo-db-06  <<EOFMYSQL
use stx_cloud_production
select count(cm.id) from cloud_transcriber ct inner join cloud_member cm on cm.id = ct.member_id and cm.state='running' and ct.instance < cm.size and time_to_sec(timediff(now(),cm.state_time)) < 4500 order by cm.host;
quit
EOFMYSQL`

results=$(echo $test|cut -d")" -f2 )

#checking to see if any agents failed

if (( "$results" < " 90" ));
then

	if (( "$results" < "8444));
	then
		echo -n "CRITICAL Number of Cloud ($results) workers too low."
  		return 2
	else

		echo -n "WARNING Number of Cloud worker ($results) workers too low."
  		return 1
	fi
else 
# Send message that we are healthy
	echo OK $results Cloud workers up and running
	return 0
fi


