#!/usr/bin/perl -w

use strict;
use DateTime;
use DateTime::Format::Strptime;
use Getopt::Long;
use lib "/usr/local/nagios/libexec";
use utils qw(%ERRORS);

my $community=undef;
my $critical=60;
my $help=undef;
my $login=undef;
my $password=undef;
my $remote_host=undef;
my $remote_tz=undef;
my $snmp_ver="2c";
my $snmp_port=161;
my $warn=30;
my $debug;

my $local_time="";
my $local_tz="";
my $parameters="";
my $exit_code=0;

sub help {
   print "\nNagios plugin to check the time on a server using SNMP.\n";
   print "GPL licence, (c)2007 Karl Bolingbroke\n";
	print "Version 1.02\n\n";
	print "This SNMP OID is known to work on various versions of Linux and Windoze hosts,\n";
	print "and is known to NOT work on HP-UX 11.11.\n";
   print_usage();
   print <<EOT;
-c, --critical=CRITICAL
   Number of seconds the time can be off before giving critical alert. (Default: 60)
-h, --help
   Print this help message
-H, --hostname=HOST
   Name or IP address of host to check.
-C, --community=COMMUNITY NAME
   Community name for the host's SNMP agent (implies SNMP v1 or v2c with option).
-S, --snmpver=VERSION
   Version of SNMP protocol to use: 1|2c|3. (Default: 2c)
-l, --login=LOGIN
   Login for snmpv3 authentication (implies v3 protocol with MD5)
-p, --port=PORT
-w, --warn=WARN
   Number of seconds the time can be off before giving warning alert. (Default: 30)
-x, --password=PASSWORD
   Password for snmpv3 authentication
-Z, --timezone=TIMEZONE
   Timezone of the remote host.  This is necessary, because Windoze hosts don't report the timezone.

Note:
  The script will return 
    OK if the time on the remote server is < WARNING seconds off from the Nagios server.
    WARNING if the remote server's time is > WARNING and < CRITICAL seconds different.
    CRITICAL if the remote server's time > CRITICAL seconds different.
EOT
}

sub check_options {
   Getopt::Long::Configure ("bundling");
   GetOptions(
        'c:i'   => \$critical,          'critical:i'    => \$critical,
		  'd'     => \$debug,             'debug'         => \$debug,
        'h'     => \$help,              'help'          => \$help,
		  'l:s'   => \$login,             'login:s'       => \$login,
		  'p:i'   => \$snmp_port,         'port:i'        => \$snmp_port,
        'w:i'   => \$warn,              'warn:i'        => \$warn,
		  'x:s'   => \$password,          'password:s'    => \$password,
        'C:s'   => \$community,         'community:s'   => \$community,
        'H:s'   => \$remote_host,       'hostname:s'    => \$remote_host,
        'S:s'   => \$snmp_ver,          'snmpver:s'     => \$snmp_ver,
        'Z:s'   => \$remote_tz,         'timezone:s'    => \$remote_tz
   );
	if (defined ($help)) { help(); exit $ERRORS{"UNKNOWN"}};
	# Check the SNMP parameters
	if ( !defined($community) && (!defined($login) || !defined($password)) ) {
	 	print "Missing SNMP login information!\n";
		print_usage();
		exit $ERRORS{"UNKNOWN"}
	}
	if ( !defined($remote_host) ) {
		print "Missing name of host to check!\n";
		print_usage();
		exit $ERRORS{"UNKNOWN"}
	}
	if ( !defined($remote_tz) ) {
		print "Missing timezone of the remote host!\nThis is required because Windoze hosts don't report their timezone.\n";
		print_usage();
		exit $ERRORS{"UNKNOWN"}
	}
}

sub print_usage {
    print "Usage: check_time_snmp.pl -H <host> -C <SNMP community> -Z <timezone of host> [-l <SNMP login> -x <SNMP password] [-S <SNMP version 1|2c|3>] [-p <port>] [-c <critical>] [-w <warn>]\n";
}

####### MAIN PROGRAM ########
check_options();
$parameters="-v $snmp_ver";
if ( defined($login) ) {
	$parameters="-u $login -X $password ";
} else {
	$parameters="-c $community " . $parameters;
}

$local_time=`date "+%Y %m %d %H %M %S"`;

if (defined $debug) { print "snmpwalk $parameters $remote_host:$snmp_port 1.3.6.1.2.1.25.1.2|"; }
my $remote_ts=`snmpwalk -r 3 $parameters $remote_host:$snmp_port 1.3.6.1.2.1.25.1.2 2>&1`;
if ( $? > 0 ) { 
	print "WARNING - SNMP query to $remote_host failed!\n";
	exit $ERRORS{"WARNING"};
}
chomp($remote_ts);
my @remote_ts=split(/ /,$remote_ts,4);
if (defined $debug) { print "@remote_ts|"; }
@remote_ts=split(/,/,$remote_ts[3]);
my @remote_ts_1=split(/-/,$remote_ts[0]);
my $r_year=$remote_ts_1[0];
my $r_month=sprintf("%02d",$remote_ts_1[1]);
my $r_day=sprintf("%02d",$remote_ts_1[2]);
my @remote_ts_2=split(/:/,$remote_ts[1]);
my $r_hour=sprintf("%02d",$remote_ts_2[0]);
my $r_minute=sprintf("%02d",$remote_ts_2[1]);
my $r_sec=sprintf("%02d",int($remote_ts_2[2]));
if ( defined $remote_ts[2] ) {
	my @remote_tz=split(/:/,$remote_ts[2]);
	if ( defined $remote_tz[1] ) {
		$remote_tz=sprintf("%03d",$remote_tz[0]) . sprintf("%02d",$remote_tz[1]);
	} else {
		$remote_tz=$remote_tz[0];
	}
}

my $formatter = DateTime::Format::Strptime->new(pattern=>"%s");
my @local_time=split(/ /,$local_time);
if (defined $debug) { print "@local_time|"; }
my $local_ts=DateTime->new( year=>$local_time[0], month=>$local_time[1], day=>$local_time[2], hour=>$local_time[3], minute=>$local_time[4], second=>$local_time[5], time_zone=>"local",formatter =>$formatter);
$remote_ts=DateTime->new( year=>$r_year, month=>$r_month, day=>$r_day, hour=>$r_hour, minute=>$r_minute, second=>$r_sec, time_zone=>$remote_tz,formatter =>$formatter);
if (defined $debug) { print "$local_ts|$remote_ts"; }
my $diff=int($local_ts)-int($remote_ts);

if (abs($diff) > $critical) {
	print "CRITICAL - $remote_host time is off by $diff seconds!\n";
	exit $ERRORS{"CRITICAL"};
} elsif ($diff > $warn) {
	print "WARNING - $remote_host time is off by $diff seconds!\n";
	exit $ERRORS{"WARNING"};
} else {
	print "OK - $remote_host time differs by $diff seconds.\n";
	exit $ERRORS{"OK"};
}


