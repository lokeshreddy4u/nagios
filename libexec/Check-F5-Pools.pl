#!/usr/bin/perl


#/******************************************************************************
# *
# * CHECK_F5_POOLS
# *
# * Program: Linux plugin for Nagios
# * License: GPL
# * Copyright (c) 2009- Victor Ruiz (vruiz@adif.es)
# *
# * Description:
# *
# * This software checks some OID's from F5-BIGIP-LOCAL-MIB
# * ltmPoolStatus branch with pool related objects
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
# * $Id: check-f5-pools.pl,v 0.9 2009/05/07 17:15:40 savirziur Exp $
# *
# *****************************************************************************/


use strict;
use Net::SNMP qw(:snmp);
use Getopt::Std;

our($opt_h, $opt_c, $opt_t);
my %nagios_exit_codes = ('UNKNOWN' ,-1,
                         'OK'      , 0,
                         'WARNING' , 1,
                         'CRITICAL', 2,);

my @availability_color_codes = ( 'None: Pool Error',
                                 'green: Available in some capacity',
                                 'yellow: Not currently available',
                                 'red: Not available',
                                 'blue: Availability is unknown',
                                 'gray: Unlicensed');

if  ( !getopts('h:c:t:') ){
   &usage;
   exit $nagios_exit_codes{"CRITICAL"};
}

#alarm ($opt_t);

my ($session, $error) = Net::SNMP->session(
   -version     => 'snmpv2c',
   -nonblocking => 1,
   -hostname    => $opt_h,
   -community   => $opt_c,
   -port        => 161
);

if (!defined($session)) {
   printf("ERROR: %s.\n", $error);
   exit $nagios_exit_codes{"UNKNOWN"};
}


my $status = "OK";
my %ltmPoolStatusTable;
my $ltmPoolStatus = '.1.3.6.1.4.1.3375.2.2.5.5';
my $ltmPoolStatusNumber = '.1.3.6.1.4.1.3375.2.2.5.5.1.0';
my $ltmPoolStatusName = '.1.3.6.1.4.1.3375.2.2.5.5.2.1.1';
my $ltmPoolStatusAvailState = '.1.3.6.1.4.1.3375.2.2.5.5.2.1.2';
my $ltmPoolStatusEnabledState = '.1.3.6.1.4.1.3375.2.2.5.5.2.1.3';
my $ltmPoolStatusDetailReason = '.1.3.6.1.4.1.3375.2.2.5.5.2.1.5';

my %ltmPoolMbrStatusTable;
my $ltmPoolMemberStatus = '.1.3.6.1.4.1.3375.2.2.5.6';
my $ltmPoolMbrStatusNumber = '.1.3.6.1.4.1.3375.2.2.5.6.1.0';
my $ltmPoolMbrStatusPoolName = '.1.3.6.1.4.1.3375.2.2.5.6.2.1.1';
my $ltmPoolMbrStatusAvailState = '.1.3.6.1.4.1.3375.2.2.5.6.2.1.5';
my $ltmPoolMbrStatusEnabledState = '.1.3.6.1.4.1.3375.2.2.5.6.2.1.6';
my $ltmPoolMbrStatusDetailReason = '.1.3.6.1.4.1.3375.2.2.5.6.2.1.8';


my $result = $session->get_bulk_request(
   -callback       => [\&table_cb, \%ltmPoolStatusTable, $ltmPoolStatus, \$status],
   -maxrepetitions => 10,
   -varbindlist    => [$ltmPoolStatus]
);

if (!defined($result)) {
   printf("ERROR: %s.\n", $session->error);
   $session->close;
   exit $nagios_exit_codes{"UNKNOWN"};
}

my $result = $session->get_bulk_request(
   -callback       => [\&table_cb, \%ltmPoolMbrStatusTable, $ltmPoolMemberStatus, \$status],
   -maxrepetitions => 10,
   -varbindlist    => [$ltmPoolMemberStatus]
);

if (!defined($result)) {
   printf("ERROR: %s.\n", $session->error);
   $session->close;
   exit $nagios_exit_codes{"UNKNOWN"};
}

snmp_dispatcher();

$session->close;

#alarm 0;

my $oids_cnt = 0;
my %hiddenStrings;
foreach my $oid (oid_lex_sort(keys(%ltmPoolStatusTable))) {
   if ( oid_base_match($ltmPoolStatusName, $oid) ) {
      $oids_cnt++;
      $hiddenStrings{$ltmPoolStatusTable{$oid}} = substr($oid, length($ltmPoolStatusName));
   } else {
     if ( $oids_cnt >= $ltmPoolStatusTable{$ltmPoolStatusNumber} ) { last;}
   }
}


my $mbrs_cnt = 0;
my %pool_enabled_members;

foreach my $oid (oid_lex_sort(keys(%ltmPoolMbrStatusTable))) {
   if ( oid_base_match($ltmPoolMbrStatusEnabledState, $oid) ) {
      $mbrs_cnt++;

      if ( $ltmPoolMbrStatusTable{ $oid } == 1 ) {
         my $counter = $pool_enabled_members{ $ltmPoolMbrStatusTable{ $ltmPoolMbrStatusPoolName . substr($oid, length($ltmPoolMbrStatusEnabledState))}};
         if (defined($counter)){
            $counter++;
            $pool_enabled_members{ $ltmPoolMbrStatusTable{ $ltmPoolMbrStatusPoolName . substr($oid, length($ltmPoolMbrStatusEnabledState))}} = $counter;
         } else {
            $pool_enabled_members{ $ltmPoolMbrStatusTable{ $ltmPoolMbrStatusPoolName . substr($oid, length($ltmPoolMbrStatusEnabledState))}} = 1;
         }
      }

   } else {
     if ( $mbrs_cnt >= $ltmPoolMbrStatusTable{$ltmPoolMbrStatusNumber} ) { last;}
   }
}



my $enabled_pools_cnt = 0;
my $disabled_pools_cnt = 0;
my $enabled_pools = "";
my $disabled_pools = "";

my $available_pools_cnt = 0;
my $unavailable_pools_cnt = 0;
my $available_pools;
my $unavailable_pools;

foreach my $oid (oid_lex_sort(keys(%hiddenStrings))) {
   if ( $ltmPoolStatusTable{$ltmPoolStatusEnabledState . $hiddenStrings{$oid}} == 1) {
      $enabled_pools_cnt++;
      $enabled_pools = $enabled_pools . " " . $oid;

      if ( $ltmPoolStatusTable{$ltmPoolStatusAvailState . $hiddenStrings{$oid}} == 1 ) {
         $available_pools_cnt++;
         $available_pools = $available_pools . " " . $oid;
      } else {
         $unavailable_pools_cnt++;
         if ( $pool_enabled_members{ $oid } > 0 ) { 
            $unavailable_pools = $unavailable_pools . "'" . $oid . "' (" . $ltmPoolStatusTable{$ltmPoolStatusDetailReason . $hiddenStrings{$oid}} . ") ";
            $status = "CRITICAL";
         } else {
            $unavailable_pools = $unavailable_pools . "'" . $oid . "' ( All pool-members disabled ) ";
            if ($status ==  "OK") { $status = "WARNING"; }
         }

      }

   } else {
      $disabled_pools_cnt++;
      $disabled_pools = $disabled_pools . " " . $oid;
   }
}

if ( ! defined ($ltmPoolStatusTable{$ltmPoolStatusNumber}) ) { $status = "CRITICAL"; }

print "POOLS[".$ltmPoolStatusTable{$ltmPoolStatusNumber}."] = ";
print "ENABLED(" . $enabled_pools_cnt . ") - ";
if ($disabled_pools_cnt > 0) {
   print "DISABLED(" . $disabled_pools_cnt . "): " . $disabled_pools . " - ";
} else {
   print "DISABLED(" . $disabled_pools_cnt . ") - ";
}
print "AVAILABLE(" . $available_pools_cnt . ") - ";
if ($unavailable_pools_cnt > 0) {
   print "UNAVAILABLE(" . $unavailable_pools_cnt . "): " . $unavailable_pools . "\n";
} else {
   print "UNAVAILABLE(" . $unavailable_pools_cnt . ")\n";
}



exit $nagios_exit_codes{$status};




sub table_cb
{
   my ($session, $table, $OID_base, $status) = @_;

      if (!defined($session->var_bind_list)) {

      printf("ERROR: %s\n", $session->error);a
      $status = "CRITICAL";

   } else {

      # Loop through each of the OIDs in the response and assign
      # the key/value pairs to the anonymous hash that is passed
      # to the callback.  Make sure that we are still in the table
      # before assigning the key/values.

      my $next;

      foreach my $oid (oid_lex_sort(keys(%{$session->var_bind_list}))) {
         if (!oid_base_match($OID_base, $oid)) {
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
            -callback       => [\&table_cb, $table, $OID_base, \$status],
            -maxrepetitions => 10,
            -varbindlist    => [$next]
         );

         if (!defined($result)) {
            printf("ERROR: %s\n", $session->error);
            $status = "CRITICAL";
         }

      }
#      else {

         # We are no longer in the table, so print the results.

#         foreach my $oid (oid_lex_sort(keys(%{$table}))) {
#            printf("%s => %s\n", $oid, $table->{$oid});
#         }
#      }
   }
}


# Si hay problemas, preparamos una seÃ±al de timeout
$SIG{'ALRM'} = sub {
   print ("ERROR: No snmp response from $opt_h (alarm timeout)\n");
};

sub usage()
{
  print "usage:\n";
  print "$0 -h <F5-hostname or IP address> -c <snmp-community> -t <timeout for snmp-response>\n\n";
}

