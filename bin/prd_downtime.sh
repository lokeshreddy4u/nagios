#!/bin/sh

# colo-db-11 Backup Downtime
/usr/local/nagios/bin/schedule_downtime colo-db-11 "System Load" "`date --iso-8601` 22:00:00" "`date --iso-8601` 23:59:00" 1 7200 nagiosadmin "DB_BACKUP_TIME"
/usr/local/nagios/bin/schedule_downtime colo-db-11 "System Load" "`date --iso-8601` 01:00:01" "`date --iso-8601` 04:00:00" 1 14400 nagiosadmin "DB_BACKUP_TIME"
/usr/local/nagios/bin/schedule_downtime colo-db-11 "MYSQL: Check Slave" "`date --iso-8601` 22:00:00" "`date --iso-8601` 23:59:00" 1 7200 nagiosadmin "DB_BACKUP_TIME"
/usr/local/nagios/bin/schedule_downtime colo-db-11 "MYSQL: Check Slave" "`date --iso-8601` 01:01:00" "`date --iso-8601` 04:00:00" 1 14400 nagiosadmin "DB_BACKUP_TIME"

# colo-db-12 Backup Downtime
/usr/local/nagios/bin/schedule_downtime colo-db-12 "System Load" "`date --iso-8601` 01:00:00" "`date --iso-8601` 07:00:00" 1 21600 nagiosadmin "DB_BACKUP_TIME"
/usr/local/nagios/bin/schedule_downtime colo-db-12 "MYSQL: Check Slave" "`date --iso-8601` 01:00:00" "`date --iso-8601` 07:00:00" 1 21600 nagiosadmin "DB_BACKUP_TIME"

# colo-db-13 Backup Downtime
/usr/local/nagios/bin/schedule_downtime colo-db-13 "System Load" "`date --iso-8601` 04:00:00" "`date --iso-8601` 10:00:00" 1 21600 nagiosadmin "DB_BACKUP_TIME"
/usr/local/nagios/bin/schedule_downtime colo-db-13 "MYSQL: Check Slave" "`date --iso-8601` 04:00:00" "`date --iso-8601` 10:00:00" 1 21600 nagiosadmin "DB_BACKUP_TIME"

# colo-db-06 Backup Downtime
/usr/local/nagios/bin/schedule_downtime colo-db-06 "System Load" "`date --iso-8601` 03:00:00" "`date --iso-8601` 09:00:00" 1 21600 nagiosadmin "DB_BACKUP_TIME"
/usr/local/nagios/bin/schedule_downtime colo-db-06 "MYSQL: Check Slave" "`date --iso-8601` 03:00:00" "`date --iso-8601` 09:00:00" 1 21600 nagiosadmin "DB_BACKUP_TIME"
