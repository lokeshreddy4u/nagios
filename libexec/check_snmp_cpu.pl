#!/usr//bin/perl -w
#
# $Id$
#
# check_snmp_cpu_detail.pl checks detail CPU values through SNMP.
# Copied from check_snmp_cpu.pl
#
# Copyright 2007 GroundWork Open Source, Inc. (.GroundWork.)  
# All rights reserved. This program is free software; you can redistribute it and/or 
# modify it under the terms of the GNU General Public License version 2 as published 
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY 
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A 
# PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this 
# program; if not, write to the Free Software Foundation, Inc., 51 Franklin Street, 
# Fifth Floor, Boston, MA 02110-1301, USA.
#
# Change Log
#----------------
# 18-Oct-2010 - stevenpan@gmail.com
#	Initial revision
#
use strict;

my $cpu = -1;
my $userwarn = -1;
my $usercrit = -1;
my $nicewarn =-1;
my $nicecrit = -1;
my $syswarn = -1;
my $syscrit = -1;
my $idlewarn = -1;
my $idlecrit = -1;
my $waitwarn = -1;
my $waitcrit = -1;

my $debug = 0;
my $perf = 0;

#sysUpTimeInstance
my $uptimeoid = ".1.3.6.1.2.1.1.3.0";

use SNMP;
use Getopt::Long;
use Time::HiRes qw(time);
use vars qw($opt_V $opt_c $opt_s $opt_n $opt_u $opt_i $opt_D $opt_p $opt_h $opt_w);
use vars qw($opt_H $opt_m $opt_v $opt_o);
$opt_c = -1;
$opt_m = "public";
$opt_o = 161;
$opt_v = "2c";
# Watch out for this: snmpd updates every 5 secs by default
my $sleeptime = 10; # seconds
use vars qw($PROGNAME);
use lib "/usr/local/nagios/libexec";
use utils qw($TIMEOUT %ERRORS &print_revision &support &usage);

sub print_help ();
sub print_usage ();

my $tmp_dir = "/var/tmp";
$PROGNAME = "check_snmp_cpu_detail";

Getopt::Long::Configure('bundling');
my $status = GetOptions ( 
	"V"   => \$opt_V, "progVersion"	=> \$opt_V,
	"H=s" => \$opt_H, "host=s"		=> \$opt_H,
	"C=s" => \$opt_m, "Community=s"	=> \$opt_m,
	"t"   => \$TIMEOUT, "timeout"	=> \$TIMEOUT,
	"S"   => \$sleeptime, "sleeptime=s"	=> \$sleeptime,
	"v"   => \$opt_v, "version"		=> \$opt_v,
	"u=s" => \$opt_u, "user=s"		=> \$opt_u,
	"n=s" => \$opt_n, "nice=s"   	=> \$opt_n,
	"s=s" => \$opt_s, "system=s" 	=> \$opt_s,
	"i=s" => \$opt_i, "idle=s"		=> \$opt_i,
	"w=s" => \$opt_w, "wait=s"		=> \$opt_w,
	"D"   => \$opt_D, "debug"		=> \$opt_D,
	"o"   => \$opt_o, "port"		=> \$opt_o,
	"p"   => \$opt_p, "performance"	=> \$opt_p,
	"h"   => \$opt_h, "help"		=> \$opt_h
);

if ($status == 0) { print_usage() ; exit $ERRORS{'UNKNOWN'}; }

# Need host name
if (!$opt_H) { die "-H <hostname> is required\n" }

# check snmp version
if ($opt_v && $opt_v !~ /1|2c/) { die "SNMP V1 or V2c only\n" }

# Debug switch
if ($opt_D) { $SNMP::debugging = 1; $debug = 1 }

# Cpu switch
if ($opt_c >= 0) { $cpu = $opt_c; }

# Performance switch
if ($opt_p) { $perf = 1; }

# Version
if ($opt_V) {
        print_revision($PROGNAME,'$Revision$');
        exit $ERRORS{'OK'};
}

if ($opt_h) {print_help(); exit $ERRORS{'UNKNOWN'}}

# Options checking
# Percent CPU system utilization
if ($opt_s) { 
	($syswarn, $syscrit) = split /:/, $opt_s;

	($syswarn && $syscrit) || usage ("missing value -s <warn:crit>\n");

	($syswarn =~ /^\d{1,3}$/ && $syswarn > 0 && $syswarn <= 100) &&
	($syscrit =~ /^\d{1,3}$/ && $syscrit > 0 && $syscrit <= 100) ||
		usage("Invalid value: -s <warn:crit> (system percent): $opt_s\n");

	($syscrit > $syswarn) || 
		usage("system critical (-s $opt_s <warn:crit>) must be > warning\n");
}

# Percent CPU nice utilization
if ($opt_n) {
	($nicewarn, $nicecrit) = split /:/, $opt_n;

	($nicewarn && $nicecrit) || usage ("missing value -n <warn:crit>\n");

	($nicewarn =~ /^\d{1,3}$/ && $nicewarn > 0 && $nicewarn <= 100) &&
	($nicecrit =~ /^\d{1,3}$/ && $nicecrit > 0 && $nicecrit <= 100) ||
		usage("Invalid value: -n <warn:crit> (nice percent): $opt_n\n");

	($nicecrit > $nicewarn) || 
		usage("nice critical (-n $opt_n <warn:crit>) must be > warning\n");
}

# Percent CPU user utilzation
if ($opt_u) {
	($userwarn, $usercrit) = split /:/, $opt_u;

	($userwarn && $usercrit) || usage ("missing value -u <warn:crit>\n");

	($userwarn =~ /^\d{1,3}$/ && $userwarn > 0 && $userwarn <= 100) &&
	($usercrit =~ /^\d{1,3}$/ && $usercrit > 0 && $usercrit <= 100) ||
		usage("Invalid value: -u <warn:crit> (user percent): $opt_u\n");

	($usercrit > $userwarn) || 
		usage("user critical (-u $opt_u <warn:crit>) must be < warning\n");
}

# Percent CPU idle utilzation
if ($opt_i) {
	($idlewarn, $idlecrit) = split /:/, $opt_i;

	($idlewarn && $idlecrit) || usage ("missing value -i <warn:crit>\n");

	($idlewarn =~ /^\d{1,3}$/ && $idlewarn > 0 && $idlewarn <= 100) &&
	($idlecrit =~ /^\d{1,3}$/ && $idlecrit > 0 && $idlecrit <= 100) ||
		usage("Invalid value: -i <warn:crit> (idle percent): $opt_i\n");

	($idlecrit < $idlewarn) || 
		usage("idle critical (-i $opt_i <warn:crit>) must be > warning\n");
}

# Percent CPU IO wait utilzation
if ($opt_w) {
	($waitwarn, $waitcrit) = split /:/, $opt_w;

	($waitwarn && $waitcrit) || usage ("missing value -w <warn:crit>\n");

	($waitwarn =~ /^\d{1,3}$/ && $waitwarn > 0 && $waitwarn <= 100) &&
	($waitcrit =~ /^\d{1,3}$/ && $waitcrit > 0 && $waitcrit <= 100) ||
		usage("Invalid value: -w <warn:crit> (wait percent): $opt_w\n");

	($waitcrit > $waitwarn) || 
		usage("wait critical (-w $opt_w <warn:crit>) must be < warning\n");
}

# Read /proc/stat values.  The first "cpu " line has aggregate values if
# the system is SMP, otherwise, just get the requested CPU


# Get the kernel/system statistic values from SNMP

alarm ( $TIMEOUT ); # Don't hang Nagios

my $snmp_session = new SNMP::Session (
    DestHost	=> $opt_H,
    Community 	=> $opt_m,
    RemotePort	=> $opt_o,
    Version	=> $opt_v
);

my $history_file_name = $PROGNAME . "_" . $opt_H ;
print "$tmp_dir/$history_file_name\n" if $debug;

my ($last_check_time, $tmp_user, $tmp_sys, $tmp_nice, $tmp_idle, $tmp_wait) = undef;
if ( open(FILE,"$tmp_dir/$history_file_name") ) {;
    $last_check_time = <FILE>; chomp($last_check_time);
    $tmp_user = <FILE>;        chomp($tmp_user);
    $tmp_sys = <FILE>;         chomp($tmp_sys);
    $tmp_nice = <FILE>;        chomp($tmp_nice);
    $tmp_idle = <FILE>;        chomp($tmp_idle);
    $tmp_wait = <FILE>;        chomp($tmp_wait);
    close(FILE);
} else {
    # retrieve the data from the remote host
    ($last_check_time, $tmp_user, $tmp_sys, $tmp_nice, $tmp_idle, $tmp_wait) = $snmp_session->get([
        [$uptimeoid],
        ['ssCpuRawUser',0],
        ['ssCpuRawSystem',0],
        ['ssCpuRawNice',0],
        ['ssCpuRawIdle',0],
        ['ssCpuRawWait',0]
    ]);
    check_for_errors();

    # need to sleep to get delta
    sleep $sleeptime;
}

print "time\t user\t sys\t nice\t idle\t wait\n" if $debug;
print "$last_check_time\t $tmp_user\t $tmp_sys\t $tmp_nice\t $tmp_idle $tmp_wait\n" if $debug;

my ($check_time, $user, $sys, $nice, $idle, $wait) = undef;
# retrieve the data from the remote host
($check_time, $user, $sys, $nice, $idle, $wait) = $snmp_session->get([
    [$uptimeoid],
    ['ssCpuRawUser',0],
    ['ssCpuRawSystem',0],
    ['ssCpuRawNice',0],
    ['ssCpuRawIdle',0],
    ['ssCpuRawWait',0]
]);
check_for_errors();

# save data to history file
if ( open(FILE, ">$tmp_dir/$history_file_name") ) {
    print FILE "$check_time\n";
    print FILE "$user\n";
    print FILE "$sys\n";
    print FILE "$nice\n";
    print FILE "$idle\n";
    print FILE "$wait\n";
    close(FILE);
}

print "time\t user\t sys\t nice\t idle\t wait\n" if $debug;
print "$check_time\t $user\t $sys\t $nice\t $idle $wait\n" if $debug;

alarm (0); # Done with network

# deal reboot
if ( $last_check_time > $check_time ) {
    exit (0);
}

# deal wrap
if ( $user < $tmp_user ) { $user = 4294967295 + $user +1; }
if ( $sys  < $tmp_sys  ) { $sys = 4294967295 + $sys +1;   }
if ( $nice < $tmp_nice ) { $nice = 4294967295 + $nice +1; }
if ( $idle < $tmp_idle ) { $idle = 4294967295 + $idle +1; }
if ( $wait < $tmp_wait ) { $wait = 4294967295 + $wait +1; }

# The query returns values from uptime, we want over the last sleeptime.
$user = $user - $tmp_user;
$sys  = $sys - $tmp_sys;
$nice = $nice - $tmp_nice;
$idle = $idle - $tmp_idle;
$wait = $wait - $tmp_wait;

print "SNMP raw: user: $user sys: $sys nice: $nice idle: $idle wait: $wait\n" if $debug;

# Here we convert to percents
my $total = undef;
$total = $user + $sys + +$nice + $idle + $wait;
if ( $total ) {
$user  = $user / $total * 100;
$sys   = $sys  / $total * 100;
$idle  = $idle / $total * 100;
$wait  = $wait / $total * 100;
$nice  = $nice / $total * 100;
}

# Threshold checks
my $out = undef;
my $c;

$c = ($cpu < 0) ? "ALL" : $cpu;
$out = $out."(cpu: $c) ";

$out = $out . sprintf("user: %.2f%% ", $user);
if ($usercrit > 0) {
	($user > $usercrit) ? ($out = $out . "(Critical) ") :
		($user > $userwarn) ? ($out=$out . "(Warning) ") : 
			($out=$out."(OK) ");
} else {
	$out=$out."(OK) ";
}

$out = $out .  sprintf("nice: %.2f%% ", $nice);
if ($nicecrit > 0) {
	($nice > $nicecrit) ? ($out=$out."(Critical) ") :
		($nice > $nicewarn) ? ($out=$out."(Warning) ") : 
			($out=$out."(OK) ");
} else {
	$out=$out."(OK) ";
}

$out=$out . sprintf("sys: %.2f%% ", $sys);
if ($syscrit > 0) {
	($sys > $syscrit) ? ($out=$out."(Critical) ") :
		($sys > $syswarn) ? ($out=$out."(Warning) ") : 
			($out=$out."(OK) ");
} else {
	$out=$out."(OK) ";
}

$out=$out . sprintf("idle: %.2f%% ", $idle);
if ($idlecrit > 0) {
	($idle < $idlecrit) ? ($out=$out."(Critical) ") : 
		($idle < $idlewarn) ? ($out=$out."(Warning) ") : 
			($out=$out."(OK) ");
} else {
	$out=$out."(OK) ";
}

$out=$out . sprintf("wait: %.2f%% ", $wait);
if ($waitcrit > 0) {
	($wait > $waitcrit) ? ($out=$out."(Critical) ") :
		($wait > $waitwarn) ? ($out=$out."(Warning) ") : 
			($out=$out."(OK) ");
} else {
	$out=$out."(OK) ";
}

# Main output
print "$out";

# Performance output
if ($perf) {;
	print " |";

	if ($usercrit < 0) { printf(" user=%.2f%%;;;;", $user) }
	else { printf(" user=%.2f%%;%d;%d;;", $user,$userwarn,$usercrit) }

	if ($nicecrit < 0) { printf(" nice=%.2f%%;;;;", $nice) }
	else { printf(" nice=%.2f%%;%d;%d;;", $nice,$nicewarn,$nicecrit) }

	if ($syscrit < 0) { printf(" sys=%.2f%%;;;;", $sys) }
	else { printf(" sys=%.2f%%;%d;%d;;", $sys,$syswarn,$syscrit) }

	if ($idlecrit < 0) { printf(" idle=%.2f%%;;;;", $idle) }
	else { printf(" idle=%.2f%%;%d;%d;;", $idle,$idlewarn,$idlecrit) }

	if ($waitcrit < 0) { printf(" wait=%.2f%%;;;;", $wait) }
	else { printf(" wait=%.2f%%;%d;%d;;", $wait,$waitwarn,$waitcrit) }

#`printf "user=$user;;;;\nnice=$nice;;;;\nsys=$sys;;;;\nidle=$idle;;;;\nwait=$wait;;;;\n" |/usr/local/groundwork/nagios/libexec/perfdata_app.pl -H $opt_H -S check_snmp_cpu_detail `;

}

print "\n";

# Plugin output
# $worst == $ERRORS{'OK'} ?  print "CPU OK @goodlist" : print "@badlist";

# Performance? 

if ($out =~ /Critical/) { exit $ERRORS {'CRITICAL'} }
if ($out =~ /Warning/)  { exit $ERRORS {'WARNING'}  }

exit (0); #OK

# Usage sub
sub print_usage () {
        print "Usage: $PROGNAME 
	[-C], --Community <community>
	[-h], --help
	[-H], --host
	[-i], --idle <warn:crit> percent (NOTE: idle less than x)
	[-w], --wait <warn:crit> percent
	[-n], --nice <warn:crit> percent
	[-o], --port <SNMP port>
	[-p] (output Nagios performance data)
	[-s], --system <warn:crit> percent
	[-t], --timeout
	[-u], --user <warn:crit> percent
	[-D] (debug) [-h] (help) [-V] (Version)\n";
}

# Help sub
sub print_help () {
        print_revision($PROGNAME,'$Revision$');

# Perl device CPU check plugin for Nagios

	print_usage();
	print "
-C, --Community
   SNMP Community string
-D, --debug
   Debug output
-h, --help
   Print help
-H, --host
   Hostname of the target system
-i, --idle
   If less than Percent CPU idle
-w, --wait
   Percent CPU IO wait
-n, --nice
   Percent CPU nice
-o, --port
   SNMP port to use
-p, --performance
   Report Nagios performance data after the ouput string
-s, --system=STRING
   Percent CPU system
-t, --timeout
   Plugin timeout
-u, --user
   Percent CPU user
-v, --version
   SNMP version
-V, --progVersion
   Print version of plugin
";

}

sub check_for_errors {
	if ( $snmp_session->{ErrorNum} ) {
		print "UNKNOWN - error retrieving SNMP data: $snmp_session->{ErrorStr}\n";
		exit $ERRORS{UNKNOWN};
	}
}
