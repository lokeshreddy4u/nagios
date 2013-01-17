#!/bin/ksh

# Nagios check command = Checks agent status
# Author - Jim DeNisco
# 

home=/usr/local/nagios
timestamp=`date +"%D %T"`
clockfile=$home/var/tmp/results-agent-status
# check to see if clockfile exists and if it does not seed it with zero to get started
[[ -f $clockfile ]] || echo "0" >$clockfile

#Run sql script  and put rerults in sqltest
sqltest=`mysql -u nagios -pguest --host prod-write <<EOFMYSQL
use production
SELECT count(*) from agent where in_rotation = 1 and host_name rlike 'pod-worker' and timestampdiff(minute,state_time,now()) > if(role in ('generate_sitemap'),80*60, if(role in ('download','cache'),6*60, if(role in ('transcribe'),8*60, if(role in ('channel','discovery_crawler'),12*60, if(specialty in ('periodic_seo_opportunities'),24*60,if(specialty in ('monitor_series_aggregation','periodic_factiva'),6*60,if(specialty in ('index_incremental'),3*60, if(specialty in ('periodic_seo_links_update','site_seo_update','site_seo_links_update'),3600*60,if(specialty in ('periodic_purge'),2*60,40)))))))));
quit
EOFMYSQL`

# output will look something like this "count(*) 123" so the following line will clean 
# it up and add the the count number into results.
results=$(echo $sqltest | cut -d")" -f2)

# check to see if results is greater then "0" 
# if it is "0" then update clockfile with "0" 
# if it is greater then "0" increment clockfile by 1
if [ $results -eq 0 ]
then 
	# things are good going to set the clock to zero
	echo "0" >$clockfile
else
	# Increment clock by one 
	for clock in $(tail -1 $clockfile|cut -d" " -f1)
	do
		((clock=clock+1))
		echo "$clock $timestamp $results" >> $clockfile
 	done
fi

# check clockfile to see if its 3 and if it is 
# alert with a CRITICAL error otherwise alert with OK
for alert in $(tail -1 $clockfile|cut -d" " -f1)
do
	if [ $alert -gt 2 ] 
	then
	   sqlname=`mysql -u nagios -pguest --host prod-write <<EOFMYSQL
		use production
		SELECT host_name,instance_name,role from agent where in_rotation = 1 and host_name rlike 'pod-worker' and timestampdiff(minute,state_time,now()) > if(role in ('generate_sitemap'),80*60,if(role in ('download','cache'),6*60, if(role in ('transcribe'),8*60, if(role in ('channel','discovery_crawler'),12*60, if(specialty in ('periodic_seo_opportunities'),24*60,if(specialty in ('monitor_series_aggregation','periodic_factiva'),6*60,if(specialty in ('index_incremental'),3*60, if(specialty in ('periodic_seo_links_update','site_seo_update','site_seo_links_update'),36*60,if(specialty in ('periodic_purge'),2*60,40)))))))));
		quit
		EOFMYSQL`

		echo -e "CRITICAL Agent Status has failed on\n $sqlname" 

		return 2
	else
		echo -e "OK Agent Status look good\n Queue $results"
		return 0
	fi

done 
