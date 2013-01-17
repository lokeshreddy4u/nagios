#!/usr/bin/perl

#/******************************************************************************
# *
# * CHECK_F5_VIRTUAL_ADDRESSES
# *
# * Program: Linux plugin for Nagios
# * License: GPL
# * Copyright (c) 2009- Victor Ruiz (vruiz@adif.es)
# *
# * Description:
# *
# * This software checks some OID's from F5-BIGIP-LOCAL-MIB
# * ltmVirtualAddr branch with virtual address related objects
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
# * $Id: check-f5-virtual_addrs.pl,v 0.9 2009/05/07 17:15:40 savirziur Exp $
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



my %vaddresses;
my %ltmVirtualAddrTable;
my $ltmVirtualAddr = '.1.3.6.1.4.1.3375.2.2.10.10';
my $ltmVirtualAddrNumber = '.1.3.6.1.4.1.3375.2.2.10.10.1.0';
my $ltmVirtualAddrAddr = '.1.3.6.1.4.1.3375.2.2.10.10.2.1.2';


my %ltmVirtualAddrStatusTable;
my $ltmVirtualAddrStatus = '.1.3.6.1.4.1.3375.2.2.10.14';
my $ltmVAddrStatusEnabledState = '.1.3.6.1.4.1.3375.2.2.10.14.2.1.4';
my $ltmVAddrStatusAvailState = '.1.3.6.1.4.1.3375.2.2.10.14.2.1.3';
my $ltmVAddrStatusDetailReason = '.1.3.6.1.4.1.3375.2.2.10.14.2.1.6';


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
   -callback       => [\&table_cb, \%ltmVirtualAddrTable, $ltmVirtualAddr],
   -maxrepetitions => 10,
   -varbindlist    => [$ltmVirtualAddr]
);

if (!defined($result)) {
   printf("ERROR: %s.\n", $session->error);
   $session->close;
   exit $nagios_exit_codes{'UNKNOWN'};
}


my $result = $session->get_bulk_request(
   -callback       => [\&table_cb, \%ltmVirtualAddrStatusTable, $ltmVirtualAddrStatus],
   -maxrepetitions => 10,
   -varbindlist    => [$ltmVirtualAddrStatus]
);

if (!defined($result)) {
   printf("ERROR: %s.\n", $session->error);
   $session->close;
   exit $nagios_exit_codes{'UNKNOWN'};
}

snmp_dispatcher();

$session->close;
alarm 0;


my $vaddresses_cnt = 0;
my $hiddenString = "";
my $ipAddress = "";

foreach my $oid (oid_lex_sort(keys(%ltmVirtualAddrTable))) {
   if ( oid_base_match($ltmVirtualAddrAddr, $oid) ) {
      $vaddresses_cnt++;
      $hiddenString= substr($oid, length($ltmVirtualAddrAddr));
      ($ipAddress = $ltmVirtualAddrTable{$ltmVirtualAddrAddr.$hiddenString}) =~ /(..)(..)(..)(..)(..)/;
      $ipAddress = hex($2).".".hex($3).".".hex($4).".".hex($5);
      $vaddresses{$hiddenString} = $ipAddress;
   } else {
     if ( $vaddresses_cnt >= $ltmVirtualAddrTable{$ltmVirtualAddrNumber} ) { last;}
   }
}




my $enabled_vaddresses_cnt = 0;
my $disabled_vaddresses_cnt = 0;
my $enabled_vaddresses = "";
my $disabled_vaddresses = "";

my $available_vaddresses_cnt = 0;
my $unavailable_vaddresses_cnt = 0;
my $unknown_availabity_vaddresses_cnt = 0;
my $available_vaddresses = "";
my $unavailable_vaddresses = "";
my $unknown_availabity_vaddresses = "";

my $status = "OK";

foreach my $oid (oid_lex_sort(keys(%vaddresses))) {
   if ( $ltmVirtualAddrStatusTable{$ltmVAddrStatusEnabledState . $oid} == 1) {
      $enabled_vaddresses_cnt++;
      $enabled_vaddresses = $enabled_vaddresses . "'" . $vaddresses{$oid}."'";

      if ( $ltmVirtualAddrStatusTable{$ltmVAddrStatusAvailState . $oid} == 1 ) {
         $available_vaddresses_cnt++;
         $available_vaddresses = $available_vaddresses . "'" . $vaddresses{$oid}."'";
      } else {
         if ($ltmVirtualAddrStatusTable{$ltmVAddrStatusAvailState . $oid} == 4) {
            $unknown_availabity_vaddresses_cnt++;
            $unknown_availabity_vaddresses = $unknown_availabity_vaddresses . "'" . $vaddresses{$oid}."'"; 
            next;
         }         
         $unavailable_vaddresses_cnt++;
         $unavailable_vaddresses = $unavailable_vaddresses . "'" . $vaddresses{$oid};
         $status = "CRITICAL";
      }

   } else {
      $disabled_vaddresses_cnt++;
      $disabled_vaddresses = $disabled_vaddresses . " " . $vaddresses{$oid};
   }
}


print "VADDRESS[".$ltmVirtualAddrTable{$ltmVirtualAddrNumber}."] = ";
print "ENABLED(" . $enabled_vaddresses_cnt . ") - ";
if ($disabled_vaddresses_cnt > 0) {
   print "DISABLED(" . $disabled_vaddresses_cnt . "): " . $disabled_vaddresses . " - ";
} else {
   print "DISABLED(" . $disabled_vaddresses_cnt . ") - ";
}
print "AVAILABLE(" . $available_vaddresses_cnt . "):" . $available_vaddresses." - ";
if ($unavailable_vaddresses_cnt > 0) {
   print "UNAVAILABLE(" . $unavailable_vaddresses_cnt . "): " . $unavailable_vaddresses . " - ";
} else {
   print "UNAVAILABLE(" . $unavailable_vaddresses_cnt . ") - ";
}
if ( $unknown_availabity_vaddresses_cnt > 0 ) {
   print "UNKNOWN AVAILABILITY(" . $unknown_availabity_vaddresses_cnt++ . "): " . $unknown_availabity_vaddresses . "\n"; 
} else {
   print "UNKNOWN AVAILABILITY(" . $unknown_availabity_vaddresses_cnt . ")\n";
}  





exit $nagios_exit_codes{$status};

sub table_cb
{
   my ($session, $table, $OID_base) = @_;

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
