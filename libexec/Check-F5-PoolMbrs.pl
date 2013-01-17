#!/usr/bin/perl


#/******************************************************************************
# *
# * CHECK_F5_POOL_MEMBERS
# *
# * Program: Linux plugin for Nagios
# * License: GPL
# * Copyright (c) 2009- Victor Ruiz (vruiz@adif.es)
# *
# * Description:
# *
# * This software checks some OID's from F5-BIGIP-LOCAL-MIB
# * ltmPools branch with pool members related objects
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
# * $Id: check-f5-poolmbrs.pl,v 0.9 2009/05/07 17:15:40 savirziur Exp $
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


my @AvailStateCodes = ('none - error',
			'green - available in some capacity',
			'yellow - not currently available',
			'red - not available',
			'blue - availability is unknown',
			'gray - unlicensed');

my @MonitorStatusCodes = ( 'unchecked  - enabled node that is not monitored',
			'checking   - initial state until monitor reports',
			'up         - enabled node when its monitors succeed',
			'addrdown   - node address monitor fails or forced down',
			'servdown   - node server monitor fails or forced down',
			'down       - enabled node when its monitors fail',
			'forceddown - node forced down manually',
			'maint      - in maintenance mode',
			'disabled   - the monitor instance is disabled');

my %members;

my %ltmPoolMemberTable;
my $ltmPoolMember = '.1.3.6.1.4.1.3375.2.2.5.3';
my $ltmPoolMemberNumber = '.1.3.6.1.4.1.3375.2.2.5.3.1.0';
my $ltmPoolMemberPoolName = '.1.3.6.1.4.1.3375.2.2.5.3.2.1.1';
my $ltmPoolMemberAddr = '.1.3.6.1.4.1.3375.2.2.5.3.2.1.3';
my $ltmPoolMemberPort = '.1.3.6.1.4.1.3375.2.2.5.3.2.1.4';
my $ltmPoolMemberMonitorStatus = '.1.3.6.1.4.1.3375.2.2.5.3.2.1.11';

my %ltmPoolMbrStatusTable;
my $ltmPoolMemberStatus = '.1.3.6.1.4.1.3375.2.2.5.6';
my $ltmPoolMbrStatusAvailState = '.1.3.6.1.4.1.3375.2.2.5.6.2.1.5';
my $ltmPoolMbrStatusEnabledState = '.1.3.6.1.4.1.3375.2.2.5.6.2.1.6';
my $ltmPoolMbrStatusDetailReason = '.1.3.6.1.4.1.3375.2.2.5.6.2.1.8';


if  ( !getopts('h:c:t:') ){
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
   -callback       => [\&table_cb, \%ltmPoolMemberTable, $ltmPoolMember],
   -maxrepetitions => 10,
   -varbindlist    => [$ltmPoolMember]
);

if (!defined($result)) {
   printf("ERROR: %s.\n", $session->error);
   $session->close;
   exit $nagios_exit_codes{'UNKNOWN'};
}



my $result = $session->get_bulk_request(
   -callback       => [\&table_cb, \%ltmPoolMbrStatusTable, $ltmPoolMemberStatus],
   -maxrepetitions => 10,
   -varbindlist    => [$ltmPoolMemberStatus]
);

if (!defined($result)) {
   printf("ERROR: %s.\n", $session->error);
   $session->close;
   exit $nagios_exit_codes{'UNKNOWN'};
}

snmp_dispatcher();

$session->close;

alarm 0;

my $pool_members_cnt = 0;
my $hiddenString = "";
my $ipAddress = "";

foreach my $oid (oid_lex_sort(keys(%ltmPoolMemberTable))) {
   if ( oid_base_match($ltmPoolMemberPoolName, $oid) ) {
      $pool_members_cnt++;
      $hiddenString= substr($oid, length($ltmPoolMemberPoolName));
      ($ipAddress = $ltmPoolMemberTable{$ltmPoolMemberAddr.$hiddenString}) =~ /(..)(..)(..)(..)(..)/;
      $ipAddress = hex($2).".".hex($3).".".hex($4).".".hex($5);
      $members{$hiddenString} = $ltmPoolMemberTable{$oid}."-".$ipAddress.":".$ltmPoolMemberTable{$ltmPoolMemberPort.$hiddenString};
   } else {
     if ( $pool_members_cnt >= $ltmPoolMemberTable{$ltmPoolMemberNumber} ) { last;}
   }
}

my $enabled_members_cnt = 0;
my $disabled_members_cnt = 0;
my $enabled_members = "";
my $disabled_members = "";

my $available_members_cnt = 0;
my $unavailable_members_cnt = 0;
my $available_members = "";
my $unavailable_members = "";

my $status = "OK";

foreach my $oid (oid_lex_sort(keys(%members))) {
   if ( $ltmPoolMbrStatusTable{$ltmPoolMbrStatusEnabledState . $oid} == 1) {
      $enabled_members_cnt++;
      $enabled_members = $enabled_members . " " . $members{$oid};

      if ( $ltmPoolMbrStatusTable{$ltmPoolMbrStatusAvailState . $oid} == 1 ) {
         $available_members_cnt++;
         $available_members = $available_members . " " . $members{$oid};
      } else {
         $unavailable_members_cnt++;
         $unavailable_members = $unavailable_members . "'" . $members{$oid} . "' (" . substr($ltmPoolMbrStatusTable{$ltmPoolMbrStatusDetailReason . $oid},25) . ") ";
         $status = "CRITICAL";
      }

   } else {
      $disabled_members_cnt++;
      $disabled_members = $disabled_members . " " . $members{$oid};
   }
}

print "MEMBERS[".$ltmPoolMemberTable{$ltmPoolMemberNumber}."] = ";
print "ENABLED(" . $enabled_members_cnt . ") - ";
if ($disabled_members_cnt > 0) {
   print "DISABLED(" . $disabled_members_cnt . "): " . $disabled_members . " - ";
} else {
   print "DISABLED(" . $disabled_members_cnt . ") - ";
}
print "AVAILABLE(" . $available_members_cnt . ") - ";
if ($unavailable_members_cnt > 0) {
   print "UNAVAILABLE(" . $unavailable_members_cnt . "): " . $unavailable_members . "\n";
} else {
   print "UNAVAILABLE(" . $unavailable_members_cnt . ")\n";
}

exit $nagios_exit_codes{$status};

sub table_cb
{
   my ($session, $table , $OID_base) = @_;

      if (!defined($session->var_bind_list)) {

      printf("ERROR: %s\n", $session->error);   

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
            -callback       => [\&table_cb, $table, $OID_base],
            -maxrepetitions => 10,
            -varbindlist    => [$next]
         ); 

         if (!defined($result)) {
            printf("ERROR: %s\n", $session->error);
         }
      }
   }
}


# Si hay problemas, preparamos una seÃ±al de timeout
$SIG{'ALRM'} = sub {
   print "ERROR: No snmp response from $opt_h (TIMEOUT $opt_t SECONDS)\n";
};

sub usage()
{
  print "\nUsage:\n\n";
  print "$0 -h <F5-hostname or IP address> -c <snmp-community> -t <timeout for snmp-response>\n\n";
}
