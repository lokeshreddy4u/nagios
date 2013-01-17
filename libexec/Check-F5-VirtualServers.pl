#!/usr/bin/perl

#/******************************************************************************
# *
# * CHECK_F5_VIRTUAL_SERVERS
# *
# * Program: Linux plugin for Nagios
# * License: GPL
# * Copyright (c) 2009- Victor Ruiz (vruiz@adif.es)
# *
# * Description:
# *
# * This software checks some OID's from F5-BIGIP-LOCAL-MIB
# * ltmVirtualServers branch with virtual servers related objects
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
# * $Id: check-f5-virtual_servers.pl,v 0.9 2009/05/17 09:11:40 savirziur Exp $
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

my %vserversType = (	0, 'poolbased',
			1, 'ipforward',
			2, 'l2forward',
			3, 'reject');

my $status = "OK";
my %vservers;
my %ltmVirtualServTable;
my $ltmVirtualServ = '.1.3.6.1.4.1.3375.2.2.10.1';
my $ltmVirtualServNumber = '.1.3.6.1.4.1.3375.2.2.10.1.1.0';
my $ltmVirtualServName = '.1.3.6.1.4.1.3375.2.2.10.1.2.1.1';
my $ltmVirtualServAddr = '.1.3.6.1.4.1.3375.2.2.10.1.2.1.3';
my $ltmVirtualServWildmask = '.1.3.6.1.4.1.3375.2.2.10.1.2.1.5';
my $ltmVirtualServPort = '.1.3.6.1.4.1.3375.2.2.10.1.2.1.6';
my $ltmVirtualServDefaultPool = '.1.3.6.1.4.1.3375.2.2.10.1.2.1.19';
my $ltmVirtualServType = '.1.3.6.1.4.1.3375.2.2.10.1.2.1.15';

my %ltmVirtualServStatusTable;
my $ltmVirtualServStatus = '.1.3.6.1.4.1.3375.2.2.10.13';
my $ltmVsStatusEnabledState = '.1.3.6.1.4.1.3375.2.2.10.13.2.1.3';
my $ltmVsStatusAvailState = '.1.3.6.1.4.1.3375.2.2.10.13.2.1.2';
my $ltmVsStatusDetailReason = '.1.3.6.1.4.1.3375.2.2.10.13.2.1.5';


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
   -callback       => [\&table_cb, \%ltmVirtualServTable, $ltmVirtualServ, \$status],
   -maxrepetitions => 10,
   -varbindlist    => [$ltmVirtualServ]
);

if (!defined($result)) {
   printf("ERROR: %s.\n", $session->error);
   $session->close;
   exit $nagios_exit_codes{'UNKNOWN'};
}


my $result = $session->get_bulk_request(
   -callback       => [\&table_cb, \%ltmVirtualServStatusTable, $ltmVirtualServStatus, $status],
   -maxrepetitions => 10,
   -varbindlist    => [$ltmVirtualServStatus]
);

if (!defined($result)) {
   printf("ERROR: %s.\n", $session->error);
   $session->close;
   exit $nagios_exit_codes{'UNKNOWN'};
}

snmp_dispatcher();

$session->close;
#alarm 0;


my $vservers_cnt = 0;
my $hiddenString = "";
my $ipAddress = "";

foreach my $oid (oid_lex_sort(keys(%ltmVirtualServTable))) {
   if ( oid_base_match($ltmVirtualServName, $oid) ) {
      $vservers_cnt++;
      $hiddenString= substr($oid, length($ltmVirtualServName));
      ($ipAddress = $ltmVirtualServTable{$ltmVirtualServAddr.$hiddenString}) =~ /(..)(..)(..)(..)(..)/;
      $ipAddress = hex($2).".".hex($3).".".hex($4).".".hex($5);
      $vservers{$hiddenString} = "[".$ltmVirtualServTable{$oid}."]/(".$vserversType{$ltmVirtualServTable{$ltmVirtualServType.$hiddenString}}.")/".$ipAddress.":".$ltmVirtualServTable{$ltmVirtualServPort.$hiddenString};
   } else {
     if ( $vservers_cnt >= $ltmVirtualServTable{$ltmVirtualServNumber} ) { last;}
   }
}




my $enabled_vservers_cnt = 0;
my $disabled_vservers_cnt = 0;
my $enabled_vservers = "";
my $disabled_vservers = "";


my $available_vservers_cnt = 0;
my $unavailable_vservers_cnt = 0;
my $unknown_availabity_vservers_cnt = 0;
my $available_vservers = "";
my $unavailable_vservers = "";
my $unknown_availabity_vservers = "";


foreach my $oid (oid_lex_sort(keys(%vservers))) {
   if ( $ltmVirtualServStatusTable{$ltmVsStatusEnabledState . $oid} == 1) {
      $enabled_vservers_cnt++;
      $enabled_vservers = $enabled_vservers . " '" . $vservers{$oid}."' ";

      if ( $ltmVirtualServStatusTable{$ltmVsStatusAvailState . $oid} == 1 ) {
         $available_vservers_cnt++;
         $available_vservers = $available_vservers . " '" . $vservers{$oid}."' ";
      } else {
         if ($ltmVirtualServStatusTable{$ltmVsStatusAvailState . $oid} == 4) {
            $unknown_availabity_vservers_cnt++;
            $unknown_availabity_vservers = $unknown_availabity_vservers . " '" . $vservers{$oid}."' "; 
            next;
         }
         $unavailable_vservers_cnt++;
         $unavailable_vservers = $unavailable_vservers . "'" . $vservers{$oid};
         $status = "CRITICAL";
      }

   } else {
      $disabled_vservers_cnt++;
      $disabled_vservers = $disabled_vservers . " " . $vservers{$oid};
   }
}

if ( ! defined ($ltmVirtualServTable{$ltmVirtualServNumber}) ) { $status = "CRITICAL"; }

print "VSERVERS[".$ltmVirtualServTable{$ltmVirtualServNumber}."] = ";
print "ENABLED(" . $enabled_vservers_cnt . ") - ";
if ($disabled_vservers_cnt > 0) {
   print "DISABLED(" . $disabled_vservers_cnt . "): " . $disabled_vservers . " - ";
} else {
   print "DISABLED(" . $disabled_vservers_cnt . ") - ";
}
print "AVAILABLE(" . $available_vservers_cnt . ") - ";
if ($unavailable_vservers_cnt > 0) {
   print "UNAVAILABLE(" . $unavailable_vservers_cnt . "): " . $unavailable_vservers . " - ";
} else {
   print "UNAVAILABLE(" . $unavailable_vservers_cnt . ") - ";
}
if ( $unknown_availabity_vservers_cnt > 0 ) {
   print "UNKNOWN AVAILABILITY(" . $unknown_availabity_vservers_cnt++ . "): " . $unknown_availabity_vservers . "\n"; 
} else {
   print "UNKNOWN AVAILABILITY(" . $unknown_availabity_vservers_cnt . ")\n";
}

exit $nagios_exit_codes{$status};

sub table_cb
{
   my ($session, $table, $OID_base, $status) = @_;

      if (!defined($session->var_bind_list)) {

      printf("ERROR: %s\n", $session->error);
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
#
#      }
   }
}


# Si hay problemas, preparamos una seÃ±al de timeout
$SIG{'ALRM'} = sub {
   print ("ERROR: No snmp response from $opt_h (alarm timeout)\n");
};

sub usage()
{
  print "\nUsage:\n\n";
  print "$0 -h <F5-hostname or IP address> -c <snmp-community> -t <timeout for snmp-response>\n\n";
}
