#!/bin/ksh

test=`mysql -u nagios -pguest --host prod-write  <<EOFMYSQL
use production
select count(a.id) < 5 as is_problem FROM assignment a join item_assignment_detail d on d.assignment_id = a.id join (select id from item2 order by id desc limit 2500) T on T.id = d.item_id join item2 i on T.id = i.id where unix_timestamp(i.created_time) > unix_timestamp(now()) - 600;
quit
EOFMYSQL`
results=$(echo $test| grep [1-9])


if [ "$results" != 0 ];
then
echo OK Items api agent looks good
return 0
else
	echo CRITICAL Item api agent is having a problem 
  return 2
fi
