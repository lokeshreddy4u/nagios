#! /usr/bin/perl

#/******************************************************************************
# *
# * CHECK_F5_FAILOVER
# *
# * Program: Linux plugin for Nagios
# * License: GPL
# * Copyright (c) 2009- Victor Ruiz (vruiz@adif.es)
# *
# * Description:
# *
# * This software checks some OID's from F5-BIGIP-SYSTEM-MIB
# * sysGlobalAttrs branch with failover related objects
# *
# * License Information:
# *
# * This program is free software; you can redistribute it and/or modify
# * it under the terms of the GNU General Public License as published by
# * the Free Software Foundation; either version 2 of the License, or
# * (at your option) any later version.
# *
# * This program is distributed in the hope that it will be useful,
# * but WITHOUT ANY WARRANTY; without even the implied warranty of
# * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# * GNU General Public License for more details.
# *
# * You should have received a copy of the GNU General Public License
# * along with this program; if not, write to the Free Software
# * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
# *
# * $Id: check-f5-failover.pl,v 0.9 2009/05/08 14:35:45 savirziur Exp $
# *
# *****************************************************************************/



   use strict;
   use Net::SNMP qw(:snmp);
   use Getopt::Std;

   our($opt_h, $opt_c, $opt_t, $opt_s, $opt_k, $opt_r, $opt_n, $opt_m);
   my %sysGlobalAttrTable;
   my $output_string = "";
   my $status = "OK";

   my %nagios_exit_codes = ( 'UNKNOWN' ,-1,
			     'OK'      , 0,
			     'WARNING' , 1,
			     'CRITICAL', 2,);

   my @ConfSyncStates = ('CONFIG SYNC STATE= Synchronized.',
			 'CONFIG SYNC STATE= Local config modified, recommend configsync to peer.',
			 'CONFIG SYNC STATE= Peer config modified, recommend configsync from peer.',
			 'CONFIG SYNC STATE= Config modified on both systems, manual intervention required.');

   my @FailoverActiveModes = ( 'CLUSTER MODE= Active-Standby.',
			       'CLUSTER MODE= Active-Active.');

   my @FailoverRedundancy = ( 'REDUNDANCY= Disabled.',
			      'REDUNDANCY= Enabled.');

   my @FailoverNetworking = ( 'NETWORK FAILOVER DETECTION = Disabled.',
			      'NETWORK FAILOVER DETECTION = Enabled.');

   my @FailoverStatus = ( 'FAILOVER STATUS= Standby unit in Active-Standby mode.',
			  'FAILOVER STATUS= Active unit 1 in Active-Active mode.',
			  'FAILOVER STATUS= Active unit 2 in Active-Active mode.',
			  'FAILOVER STATUS= Active unit in Active-Standby mode.');


# Some OID's of the fail-over branch of F5-BIG-IP mib
   my $sysGlobalAttr = ".1.3.6.1.4.1.3375.2.1.1.1.1";
   my $sysAttrConfigsyncState = ".1.3.6.1.4.1.3375.2.1.1.1.1.6.0";
   my $sysAttrConnAdaptiveReaperHiwat = ".1.3.6.1.4.1.3375.2.1.1.1.1.7.0";
   my $sysAttrConnAdaptiveReaperLowat = ".1.3.6.1.4.1.3375.2.1.1.1.1.8.0";
   my $sysAttrFailoverActiveMode = ".1.3.6.1.4.1.3375.2.1.1.1.1.10.0";
   my $sysAttrFailoverIsRedundant = ".1.3.6.1.4.1.3375.2.1.1.1.1.13.0";
   my $sysAttrFailoverNetwork = ".1.3.6.1.4.1.3375.2.1.1.1.1.15.0";
   my $sysAttrFailoverUnitMask = ".1.3.6.1.4.1.3375.2.1.1.1.1.19.0";


   if  ( !getopts('h:c:t:s:k:r:n:m:') ){
	&usage;
	exit $nagios_exit_codes{'UNKNOWN'};
   }

   alarm ($opt_t);

   my ($session, $error) = Net::SNMP->session(
      -version     => 'snmpv2c',
      -nonblocking => 1,
      -hostname    => $opt_h,
      -community   => $opt_c,
      -port        => 161 
   );

   if (!defined($session)) {
      printf("ERROR: %s.\n", $error);
      exit $nagios_exit_codes{'UNKNOWN'};
   }

   my $result = $session->get_bulk_request(
      -callback       => [\&table_cb, \%sysGlobalAttrTable],
      -maxrepetitions => 10,
      -varbindlist    => [$sysGlobalAttr]
   );

   if (!defined($result)) {
      printf("ERROR: %s.\n", $session->error);
      $session->close;
      exit $nagios_exit_codes{'UNKNOWN'};
   }

   snmp_dispatcher();

   $session->close;

 

   if ( $sysGlobalAttrTable{$sysAttrConfigsyncState} !~ /^$opt_s - / )
   { $status = "WARNING"; } else { $status = "OK"; };
   $output_string = @ConfSyncStates[ int(substr($sysGlobalAttrTable{$sysAttrConfigsyncState}, 0, 1 ) ) ];

   if ( $sysGlobalAttrTable{$sysAttrFailoverActiveMode} != $opt_k )
   { $status = "WARNING"; } else { ( ($status eq "WARNING") ? $status : "OK" ) };
   $output_string = $output_string . @FailoverActiveModes[$sysGlobalAttrTable{$sysAttrFailoverActiveMode}];

   if ( $sysGlobalAttrTable{$sysAttrFailoverIsRedundant} != $opt_r )
   { $status = "CRITICAL" };
   $output_string = $output_string . @FailoverRedundancy[$sysGlobalAttrTable{$sysAttrFailoverIsRedundant}];

   if ( $sysGlobalAttrTable{$sysAttrFailoverNetwork} != $opt_n )
   { $status = "WARNING" };
   $output_string = $output_string . @FailoverNetworking[$sysGlobalAttrTable{$sysAttrFailoverNetwork}];

   if ( $sysGlobalAttrTable{$sysAttrFailoverUnitMask} != $opt_m )
   { $status = "WARNING";
     $output_string = $output_string . @FailoverStatus[$sysGlobalAttrTable{$sysAttrFailoverUnitMask}] . "¡¡¡CONMUTED FAILOVER STATUS!!!";    
   }else{;
     $output_string = $output_string . @FailoverStatus[$sysGlobalAttrTable{$sysAttrFailoverUnitMask}];
   }
   alarm 0;
   print $output_string,"\n";
   exit $nagios_exit_codes{$status};

############################################################################

   sub table_cb
   {
      my ($session, $table) = @_;

      if (!defined($session->var_bind_list)) {

         printf("ERROR: %s\n", $session->error);   

      } else {

         # Loop through each of the OIDs in the response and assign
         # the key/value pairs to the anonymous hash that is passed
         # to the callback.  Make sure that we are still in the table
         # before assigning the key/values.

         my $next;

         foreach my $oid (oid_lex_sort(keys(%{$session->var_bind_list}))) {
            if (!oid_base_match($sysGlobalAttr, $oid)) {
               $next = undef;
               last;
            }
            $next = $oid; 
            $table->{$oid} = $session->var_bind_list->{$oid};   
         }

         # If $next is defined we need to send another request 
         # to get more of the table.

         if (defined($next)) {

            $result = $session->get_bulk_request(
               -callback       => [\&table_cb, $table],
               -maxrepetitions => 10,
               -varbindlist    => [$next]
            ); 

            if (!defined($result)) {
               printf("ERROR: %s\n", $session->error);
            }

         }
      }
   }

# Si hay problemas, para que no se cuelgue Nagios preparamos una seÃƒÂ±al de timeout
   $SIG{'ALRM'} = sub {
      print ("ERROR: No snmp response from $opt_h (alarm timeout)\n");
      exit $nagios_exit_codes{'UNKNOWN'};
   };

sub usage()
{
  print "\nUsage:\n\n";
  print " $0 -h <F5-hostname or IP address> -c <snmp-community>
-t <timeout for snmp-response> -s <syncState:0|1|2|3> -k <cluster activeMode:0|1>
-r <redundancy:0|1> -n <netFailover:0|1> -m <machineState:0|1|2|3>\n\n";

  print "OPTIONS:\n\n";

  print " -s (Expected sync state)\n";
  print "		0: Sincronized\n";
  print "		1: local config modified\n";
  print "		2: peer config modified\n";
  print "		3: local and peer config modified\n\n";

  print " -k (Cluster working mode)\n";
  print "		0: Active-Standby\n";
  print "		1: Active-Active\n\n";

  print " -r (Redundancy enabled)\n";
  print "		0: Disabled\n";
  print "		1: Enabled\n\n";

  print " -n (Network failover Detection)\n";
  print "		0: serial link back-network connection\n";
  print "		1: Network connection\n\n";

  print " -m (active/standby mode of the unit in the cluster)\n";

  print "		0: Standby (when activeMode=0)\n";
  print "		1: Active (Referred to unit 1 when activeMode=1)\n";
  print "		2: Active (Referred to unit 2 when activeMode=1)\n";
  print "		3: Active (when activeMode=0)\n\n";
}
