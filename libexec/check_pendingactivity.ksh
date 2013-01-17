#!/usr/bin/ksh
#------------------------------------------
#
# Created By : Jim DeNisco  
# File Name : check_pendingactivity.ksh
# Creation Date : 11-01-2011
# Last Modified : Tue 11 Jan 2011 02:20:29 PM EST
# Category : Nagios Monitoring Tools
# Purpose : Check Pending Activities
# Version : 0.9
#
#------------------------------------------

test_file=/usr/local/nagios/var/tmp/pending_activity.tmp

test=`mysql -u nagios -pguest --host prod-write  <<EOFMYSQL
use production
SELECT st.name,p.role,count(*) FROM pending_activity p
join item_assignment_detail d on p.assignment_id = d.assignment_id
join item2 i on d.item_id = i.id
join source2 s on i.source_id = s.id
join site st on s.site_id = st.id
group by 1,2
order by 3 desc;
quit

EOFMYSQL`

#echo "Test == $test"
echo "$test" > $test_file
results=$(head -10 $test_file)
resultshigh=$(cat $test_file|awk -F"|" 'NR==2''{print $1}'| awk '{print $3}')


	echo "OK pending activity list 
$results"
	return 0


