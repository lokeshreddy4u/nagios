#!/bin/ksh

# Nagios check command = mysql item processing degraded
# Author - Jim DeNisco
# 

home=/usr/local/nagios/
clockfile=$home/var/tmp/ds-ramp-app-13
# check to see if clockfile exists and if it does not seed it with zero to get started
[[ -f $clockfile ]] || echo "0" >$clockfile

#Run python script  and put results in ds12test
ds13test=`/usr/local/nagios/libexec/dataservices-13.py`
err=$?

# output will look something like this 
# OK: ramp-app-13 0.0174221992493 Thu Dec  9 12:06:03 2010
# 

# check to see if err is equal to "0" 
# if it equals "0" then update clockfile with "0" 
# if it's not equal to "0" increment clockfile by 1
if [ $err -eq 0 ]
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

# check clockfile to see if its greater then 1 and if it is 
# alert with a CRITICAL error otherwise alert with OK
for alert in $(cat $clockfile)
do
	if [ $alert -gt 1 ] 
	then
		echo "CRITICAL ramp-app-13 dataservice is in trouble"
		echo "$ds13test"
		return 2
	else
		echo "ramp-app-13 Data Services: OK"
		echo "$ds13test"
		return 0
	fi

done 
