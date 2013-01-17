#!/bin/ksh
#------------------------------------------
#
# Created By : Jim DeNisco  
# File Name : check_agent_restart.ksh
# Creation Date : 09-02-2011
# Last Modified : Wed 09 Feb 2011 02:21:34 PM EST
# Category : nagios monitoring tools
# Purpose : restart agents 
# Version : 0.9
#
#------------------------------------------

date >> /var/log/podzinger-status
service podzinger status >> /var/log/podzinger-status 



