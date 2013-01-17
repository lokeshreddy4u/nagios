#!/usr/bin/ksh
#------------------------------------------
#
# Created By : Jim DeNisco  
# File Name : check_processlist.ksh
# Creation Date : 11-01-2011
# Last Modified : Tue 11 Jan 2011 12:05:04 PM EST
# Category : Nagios Tools
# Purpose : Check prod-write process list and alert if its high
# Version : 0.9
#
#------------------------------------------


test_file=/usr/local/nagios/var/tmp/processlist.tmp

test=`mysql -u root -paibuild --host prod-write  <<EOFMYSQL
show full PROCESSLIST;
quit
EOFMYSQL`
echo "$test" > $test_file
results=$(cat $test_file| egrep -i "query|wait " )
resultscount=$(cat $test_file | egrep -i "query|wait " | wc -l )

echo "results count  == $resultscount"
echo "results ==  $results"

if [ "$resultscount" -ge 15 ]; then
	echo "CRITICAL 
	processes running in query or wait state $resultscount
	$results"
        return 2

elif [ "$resultscount" -ge 10 ]; then

        echo "WARNING 
        processes running in query or wait state $resultscount
	$results"
	return 1

else
	echo "OK prod-write process list looks good $resultscount running"
	return 0
fi


