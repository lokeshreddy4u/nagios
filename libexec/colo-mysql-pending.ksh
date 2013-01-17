#!/bin/ksh

# Nagios check command = mysql item processing degraded
# Author - Jim DeNisco
# 

home=/usr/local/nagios
timestamp=`date +"%D %T"`
clockfile=$home/var/tmp/results-pending
# check to see if clockfile exists and if it does not seed it with zero to get started
[[ -f $clockfile ]] || echo "0" >$clockfile

#Run sql script  and put rerults in sqltest
sqltest=`mysql -u nagios -pguest --host prod-write <<EOFMYSQL
use production
select count(*) from pending_activity where role in ('download','cache','transcribe','classify','groom') and priority <= 60 and specialty != 'transcribe_htx'and start_not_before_time < now();
quit
EOFMYSQL`

# output will look something like this "count(*) 123" so the following line will clean 
# it up and add the the count number into results.
results=$(echo $sqltest | cut -d")" -f2)

# check to see if results is less then "2000" 
# if it less then "2000" then update clockfile with "0" 
# if it's greater then "2000" increment clockfile by 1
if [ $results -gt 2000 ]
then 
	# Increment clock by one 
	for clock in $(tail -1 $clockfile|cut -d" " -f1)
	do
		((clock=clock+1))
		echo "$clock $timestamp $results" >> $clockfile
 	done
else
	# things are good going to set the clock to zero
	echo "0" >$clockfile
fi

# check clockfile to see if its greater then 3 and if it is 
# alert with a CRITICAL error otherwise alert with OK
for alert in $(tail -1 $clockfile|cut -d" " -f1)
do
	if [ $alert -gt 3 ] 
	then
		echo -e "CRITICAL pending items have been over 2000 for more then 15min\n $(more +2 $clockfile)" 
		return 2
	else
		echo -e "OK pending items look good\n Queue $results"
		return 0
	fi

done 
