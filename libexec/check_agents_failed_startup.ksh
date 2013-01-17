#!/bin/ksh

test=`mysql -u nagios -pguest --host prod-write  <<EOFMYSQL
use production
SELECT ag.id,ag.host_name,ag.instance_name,count(a.assignment_id) FROM activity a join agent ag on a.agent_id = ag.id where a.state in ("started","cancel_requested") group by ag.id having count(a.assignment_id) > 1;
quit
EOFMYSQL`
results=$(echo $test| grep [1-9])


if [ "$results" != 0 ];
then
echo OK $runningcount Agents started up OK
return 0
else
	echo CRITICAL Agents failed at startup
  return 2
fi
