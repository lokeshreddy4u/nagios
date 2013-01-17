#!/usr/bin/python
#====================================================================
# What's this ?
#====================================================================
# Script designed for nagios
#
# Tested with Nagios 2.9 Python 2.3.4 sun ldap directory server 5_2 patch 3
# should work with any ldap
# Checks telephoneNumber of an account to see if replication from master to slave
# ldap servers is ok
# searches telephoneNumber of an ldap account using anonymous query
# this account must be allow anonymous queries
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#====================================================================

import ldap
import ldap.modlist as modlist
import time
import datetime
import sys

def verif_modif_ldap(server,ATTR,BASE,SCOPE,FILTER):
	
        ## open ldap connection no need to bind using anonymous
	print server,
	try:
		l = ldap.open(server)
	except ldap.LDAPError, erreur_ldap:
		print  erreur_ldap[0]['desc'],
                return 2


        ## retrieve all attributes - again adjust to your needs - see documentation for more options
	try:
		ldap_result_id = l.search(BASE, SCOPE, FILTER,ATTR)
		result_set = []
		while 1:
			result_type, result_data = l.result(ldap_result_id, 0)
			if (result_data == []):
				break
			else:
				# dealing with multiple results
				if result_type == ldap.RES_SEARCH_ENTRY:
					result_set.append(result_data)
					if len(result_set) == 0:
						print "No Results.",
				for i in range(len(result_set)):
					for entry in result_set[i]:                 
						try:
							# here is phone number
							phone = entry[1]['telephoneNumber'][0]
							print ":%s" %(phone),
							return phone
						except:
							pass
    
	except ldap.LDAPError,erreur_ldap :
		print erreur_ldap[0]['desc'],
                return 2


        # Its nice to the server to disconnect and free resources when done
        lmaster.unbind_s()
	lslave.unbind_s()
	return 2



# MAIN

# Nagios states :
STATE_OK = 0
STATE_WARNING = 1
STATE_CRITICAL = 2
STATE_UNKNOWN = 3


# here are paramters to construct ldap query

#None neens ALL
retrieveAttributes = None
#baseDN = "o=mycompagny, c=com"
baseDN = "o=podzinger, c=local"
searchScope = ldap.SCOPE_SUBTREE
#account to retrieve
searchFilter = "mail=lreddy@ramp.com"

#arguments are masterldap hostname or ip, slaveldap hostname or ip

if len(sys.argv) != 3:
  sys.exit("Check master and slave telephonenumber sync.\n\nUsage : check_ldap_replication.py master_hostname slave_hostname")

# test if the telephonenumber of slave-server's account is master like

if verif_modif_ldap(sys.argv[1],retrieveAttributes,baseDN,searchScope,searchFilter) == verif_modif_ldap(sys.argv[2],retrieveAttributes,baseDN,searchScope,searchFilter):
	print "--> replication OK"
	sys.exit(STATE_OK)
	      
else :
	print "--> replication CRITICAL" 
	sys.exit(STATE_CRITICAL)


