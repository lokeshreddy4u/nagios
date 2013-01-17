#!/bin/ksh

# Nagios check command = mysql item processing degraded
# Author - Jim DeNisco
# 

home=/usr/local/nagios/
clockfile=$home/var/tmp/results-processing-degraded
# check to see if clockfile exists and if it does not seed it with zero to get started
[[ -f $clockfile ]] || echo "0" >$clockfile

#Run sql script  and put rerults in sqltest
sqltest=`mysql -u nagios -pguest --host prod-write <<EOFMYSQL
use production
select count(*) from agent where role ='process_item' and state <> 'stopped' and host_name <> 'rlau-laptop' and timestampdiff(minute,state_time,now()) > 25;
quit
EOFMYSQL`

# comment out the above command and uncomment the line below and change value for testing
#sqltest="count(*) 25"

# output will look something like this "count(*) 0" so the following line will clean 
# it up and add the the count number into results.
results=$(echo $sqltest | cut -d")" -f2)

# check to see if results is equal to "0" 
# if it equals "0" then update clockfile with "0" 
# if it's not equal to "0" increment clockfile by 1
if [ $results -eq 0 ]
then 
	# things are good going to set the clock to zero
	echo "0" >$clockfile
else
	# Increment clock by one 
	for clock in $(cat $clockfile)
	do
		((clock=clock+1))
		echo $clock > $clockfile
 	done
fi

# check clockfile to see if its greater then 3 and if it is 
# alert with a CRITICAL error otherwise alert with OK
for alert in $(cat $clockfile)
do
	if [ $alert -gt 3 ] 
	then
		echo "CRITICAL mysql item processing is degraded"  
		return 2
	else
		echo "OK mysql item processing is on time"
		return 0
	fi

done 
