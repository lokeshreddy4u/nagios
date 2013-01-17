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
select count(delay) from (select id, host, size, state, state_time, (timestampdiff(second,state_time,now())) as delay from cloud_member where state <> 'disabled'  and state <> 'stopped' and size > 0 ) as tot_delay where delay > 600;
quit
EOFMYSQL`

results=$(echo $test|cut -d")" -f2 )

#checking to see if any agents failed

if (( "$results" >= "1" ));
then
# if we have a failed host let get host_name and instance_name

	testhost=`mysql -u nagios -pguest --host colo-db-06  <<EOFMYSQL1
	use stx_cloud_production
	select host,state_time from (select id, host, size, state, state_time, (timestampdiff(second,state_time,now())) as delay from cloud_member where state <> 'disabled'  and state <> 'stopped' and size > 0 ) as tot_delay where delay > 600;
	quit
EOFMYSQL1`


# write message to nagios to send alert

	echo -n "CRITICAL Cloud is having an issue.
	Here is the host and state_time
	$testhost
"
  return 2
else 
# Send message that we are healthy
echo OK Cloud is Healthy
return 0
fi


