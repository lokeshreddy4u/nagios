#! /usr/bin/perl -w
#
# check_apc_pdu.pl - nagios plugin
#
#
# Copyright (C) 2007 Marius Rieder <marius.rieder@inf.ethz.ch>
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
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#

use POSIX;
use strict;
use lib "nagios/plugins" ;
use utils qw($TIMEOUT %ERRORS &print_revision &support);

use Net::SNMP;
use Getopt::Long;
Getopt::Long::Configure('bundling');

my $PROGNAME = "check_apc_pdu";
my $VERSION  = "v1.0";

sub print_help ();
sub usage ();
sub process_arguments ();
sub snmp_connect();

my $status;
my %loadState = ('1'=>'phaseLoadNormal',
                 '2'=>'phaseLoadLow',
		 '3'=>'phaseLoadNearOverload',
		 '4'=>'phaseLoadOverload');

my $timeout ;
my $state = "UNKNOWN";
my $answer = "";
my $snmpkey=0;
my $snmpoid=0;
my $key = 0;
my $community = "public";
my $maxmsgsize = 1472 ; # Net::SNMP default is 1472
my ($seclevel, $authproto, $secname, $authpass, $privpass, $auth, $priv, $context);
my $port = 161;
my @snmpoids;
my $rPDUOutletStatusOutletName = '.1.3.6.1.4.1.318.1.1.12.3.5.1.1.2';
my $rPDUOutletStatusOutletState = '.1.3.6.1.4.1.318.1.1.12.3.5.1.1.4';
my $rPDULoadStatus = '.1.3.6.1.4.1.318.1.1.12.2.3.1.1';
my $rPDUPowerSupplyDevice = '.1.3.6.1.4.1.318.1.1.12.4.1';
my $hostname;
my $session;
my $error;
my $response;
my %outletStatus;
my %outletMask;
my $snmp_version = 1;
my $opt_h ;
my $opt_V ;
my $opt_o ;
my $opt_a ;

# Just in case of problems, let's not hang Nagios
$SIG{'ALRM'} = sub {
     print ("ERROR: No snmp response from $hostname (alarm timeout)\n");
     exit $ERRORS{"UNKNOWN"};
};

#Option checking
$status = process_arguments();

if ($status != 0)
{
	print_help() ;
	exit $ERRORS{'OK'};
}

alarm($timeout);

# Opening SNMP Session
snmp_connect();

push(@snmpoids,$rPDUOutletStatusOutletName);
push(@snmpoids,$rPDUOutletStatusOutletState);
push(@snmpoids,$rPDULoadStatus);
push(@snmpoids,$rPDUPowerSupplyDevice);

foreach $snmpoid (@snmpoids) {
   if ( $snmp_version =~ /3/ ) {
      if (!defined($response = $session->get_table($snmpoid, -contextname => $context))) {
	 $answer=$session->error;
	 $session->close;
	 $state = 'CRITICAL';
	 print ("$state: $answer for $snmpoid\n");
	 exit $ERRORS{$state};
      }
   } else {
      if (!defined($response = $session->get_table($snmpoid))) {
	 $answer=$session->error;
         $session->close;
         $state = 'CRITICAL';
         print ("$state: $answer for $snmpoid\n");
         exit $ERRORS{$state};
      }
   }

   foreach $snmpkey (keys %{$response}) {
      $snmpkey =~ /^$snmpoid\.(\d+).*$/;
      $key = $1;
      $outletStatus{$key}{$snmpoid} = $response->{$snmpkey};
   }
}

$session->close;
alarm(0);

$state = 'OK';

if ($outletStatus{1}{$rPDUPowerSupplyDevice} eq 2) {
   $state = 'CRITICAL';
   $answer = ' Supply1 Failed!';
} elsif ($outletStatus{2}{$rPDUPowerSupplyDevice} eq 2) {
   $state = 'CRITICAL';
   $answer = ' Supply2 Failed!';
}

if ($outletStatus{3}{$rPDULoadStatus} eq 3) {
   $state = 'WARNING';
   $answer = 'Near Overload '.$outletStatus{2}{$rPDULoadStatus}.'A';
} elsif ($outletStatus{3}{$rPDULoadStatus} eq 4) {
   $state = 'CRITICAL';
   $answer = 'Overload! '.$outletStatus{2}{$rPDULoadStatus}.'A';
}

foreach $key (sort keys %outletStatus) {
   if (!%outletMask) {
      if (!$outletStatus{$key}{$rPDUOutletStatusOutletState}) {
	 $answer .= " ".$outletStatus{$key}{$rPDUOutletStatusOutletName}.'is off!';
	 $state = 'CRITICAL';
      }
   } elsif (exists $outletMask{$key})  {
      if ( $outletMask{$key} ne $outletStatus{$key}{$rPDUOutletStatusOutletState} ) {
	 $answer .= " ".$outletStatus{$key}{$rPDUOutletStatusOutletName};
	 $answer .= $outletStatus{$key}{$rPDUOutletStatusOutletState} ? ' is on!' : ' is off!';
	 $state = 'CRITICAL';
      }
      delete $outletMask{$key};
   } elsif (exists $outletMask{$outletStatus{$key}{$rPDUOutletStatusOutletName}})  {
      if ( $outletMask{$outletStatus{$key}{$rPDUOutletStatusOutletName}} ne $outletStatus{$key}{$rPDUOutletStatusOutletState} ) {
         $answer .= " ".$outletStatus{$key}{$rPDUOutletStatusOutletName};
         $answer .= $outletStatus{$key}{$rPDUOutletStatusOutletState} ? ' is on!' : ' is off!';
         $state = 'CRITICAL';
      }
      delete $outletMask{$outletStatus{$key}{$rPDUOutletStatusOutletName}};
   }
}

foreach $key (sort keys %outletMask) {
   $answer .= " Outlet $key not found.";
   $state = $state == 'CRITICAL' ? 'CRITICAL' : 'WARNING';
}

if (!$answer) {
   $answer = ' All Outlets ok.';
}

my $perfdata = sprintf("load=%d", $outletStatus{2}{$rPDULoadStatus});

print ("$state:$answer |$perfdata\n");
exit $ERRORS{$state};

sub usage (){
        printf "\nMissing arguments!\n";
        printf "\n";
        printf "check_apc_pdu -H <HOSTNAME> [-C <READCOMMUNITY>] [-p <PORT>]\n";
        printf "Copyright (C) 2007 Marius Rieder <marius.rieder\@inf.ethz.ch>\n";
        printf "\n\n";
        support();
        exit $ERRORS{"UNKNOWN"};
}

sub print_help (){
	printf "check_apc_pdu plugin for Nagios monitors operational \n";
	printf "status and load of a apc pdu\n";
	printf "\nUsage:\n";
	printf "   -H (--hostname)   Hostname to query - (required)\n";
	printf "   -C (--community)  SNMP read community (defaults to public,\n";
	printf "   -v (--snmp_version)  1 for SNMP v1 (default)\n";
	printf "                        3 for SNMPv3 (requires -U option)\n";
	printf "   -p (--port)       SNMP port (default 161)\n";
	printf "   -o (--on)         Outlets (name or number) must be on\n";
	printf "   -O (--off)        Outlets (name or number) must be off\n";
	printf "   -t (--timeout)    seconds before the plugin times out (default=$TIMEOUT)\n";
	printf "   -L (--seclevel)   choice of \"noAuthNoPriv\", \"authNoPriv\", or	\"authPriv\"\n";
	printf "   -U (--secname)    username for SNMPv3 context\n";
	printf "   -c (--context)    SNMPv3 context name (default is empty string)\n";
	printf "   -A (--authpass)   authentication password (cleartext ascii)\n";
	printf "   -a (--authproto)  Authentication protocol ( MD5 or SHA1)\n";
	printf "   -X (--privpass)   privacy password (cleartext ascii)\n";
	printf "   -M (--maxmsgsize) Max message size - usefull only for v1 or v2c\n";
	printf "   -V (--version)    Plugin version\n";
	printf "   -h (--help)       usage help \n\n";
	print_revision($PROGNAME, $VERSION);
}

sub process_arguments() {
	$status = GetOptions(
	"V"   => \$opt_V, "version"    => \$opt_V,
	"h"   => \$opt_h, "help"       => \$opt_h,
	"p=i" => \$port,  "port=i"     => \$port,
	"H=s" => \$hostname, "hostname=s" => \$hostname,
	"o=s"   => \$opt_o, "on=s"         => \$opt_o,
	"O=s"   => \$opt_a, "off=s"        => \$opt_a,
	"v=i" => \$snmp_version, "snmp_version=i"  => \$snmp_version,
	"C=s" => \$community,"community=s" => \$community,
	"L=s" => \$seclevel, "seclevel=s" => \$seclevel,
	"a=s" => \$authproto, "authproto=s" => \$authproto,
	"U=s" => \$secname,   "secname=s"   => \$secname,
	"A=s" => \$authpass,  "authpass=s"  => \$authpass,
	"X=s" => \$privpass,  "privpass=s"  => \$privpass,
	"c=s" => \$context,   "context=s"   => \$context,
	"M=i" => \$maxmsgsize, "maxmsgsize=i" => \$maxmsgsize,
	"t=i" => \$timeout,    "timeout=i" => \$timeout,
	);

	if ($status == 0){
		print_help() ;
		exit $ERRORS{'OK'};
	}

	if ($opt_V) {
		print_revision($PROGNAME, $VERSION);
		exit $ERRORS{'OK'};
	}

	if ($opt_h) {
		print_help();
		exit $ERRORS{'OK'};
	}

	unless (defined $timeout) {
	   $timeout = $TIMEOUT;
	}

	if ($snmp_version =~ /3/ ) {
	   # Must define a security level even though default is noAuthNoPriv
	   # v3 requires a security username

	   if (defined $seclevel  && defined $secname) {
	      # Must define a security level even though defualt is noAuthNoPriv
	      unless ($seclevel eq 'authNoPriv' ) {
		 print ":$seclevel:\n";
		 usage();
		 exit $ERRORS{"UNKNOWN"};
	      }

	      # Authentication wanted
	      if ($seclevel eq ('authNoPriv' || 'authPriv') ) {

		 unless ($authproto eq ('MD5' || 'SHA1') ) {
		    usage();
		    exit $ERRORS{"UNKNOWN"};
		 }

		 if ( !defined $authpass) {
		    usage();
		    exit $ERRORS{"UNKNOWN"};
		 }
	      }

	      # Privacy (DES encryption) wanted
	      if ($seclevel eq  'authPriv' ) {

		 if (! defined $privpass) {
		    usage();
		    exit $ERRORS{"UNKNOWN"};
		 }
	      }

	      unless ( defined $context) {
		 $context = "";
	      }
	   } else {
	      usage();
	      exit $ERRORS{"UNKNOWN"};
	   }
	} #end snmpv3

	unless ( defined $community ) {
	   $community = 'public';
	}

	if ($opt_o) {
	   map { $outletMask{$_}=1 } split(/\,/, $opt_o);
	}

	if ($opt_a) {
	   map { $outletMask{$_}=0 } split(/\,/, $opt_a);
	}

	unless (defined $timeout) {
		$timeout = $TIMEOUT;
	}

	if (! utils::is_hostname($hostname)){
		usage();
		exit $ERRORS{"UNKNOWN"};
	}
}

sub snmp_connect() {
   if ( $snmp_version =~ /3/ ) {
      if ($seclevel eq 'noAuthNoPriv') {
         ($session, $error) = Net::SNMP->session(
               -hostname  => $hostname,
               -port      => $port,
               -version  => $snmp_version,
               -username => $secname,
            );
      }elsif ( $seclevel eq 'authNoPriv' ) {
         ($session, $error) = Net::SNMP->session(
               -hostname  => $hostname,
               -port      => $port,
               -version  => $snmp_version,
               -username => $secname,
               -authprotocol => $authproto,
               -authpassword => $authpass
            );
      }elsif ($seclevel eq 'authPriv' ) {
         ($session, $error) = Net::SNMP->session(
               -hostname  => $hostname,
               -port      => $port,
               -version  => $snmp_version,
               -username => $secname,
               -authprotocol => $authproto,
               -authpassword => $authpass,
               -privpassword => $privpass
            );
      }
   } else {
      ($session, $error) = Net::SNMP->session(
            -hostname   => $hostname,
            -community  => $community,
            -port       => $port,
            -version    => $snmp_version,
         );
   }

   if (!defined($session)) {
      $state='UNKNOWN';
      $answer=$error;
      print ("$state: $answer");
      exit $ERRORS{$state};
   }
}
