#! /usr/bin/perl
#
# check_bigip_vs  -  Check BigIP Virtual Servers status
#
# Designed for F5 BigIP 4.5 and LTM 9.x.
#
# Copyright (C) 2006-2007 Thomas Guyot-Sionnest <tguyot@gmail.com>
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

use strict;
use warnings;
use vars qw($PROGNAME $VERSION $snmpcmd %bip);
use Nagios::Plugin;

$PROGNAME = 'check_bigip_vs';
$VERSION = '2.02';
$snmpcmd = '/usr/bin/snmpget';

# BigIP config. For each bigip version, there is the base OID and possible
# status codes. The array defined for each status codes is passed directly
# to the nagios_exit function.
%bip = (
  '4.5' => {
    'OID' => '.1.3.6.1.4.1.3375.1.1.3.2.1.3.',
    '1' => ['WARNING', 'Virtual Server is Disabled'],
    '2' => ['OK', 'Virtual Server is Up and available'],
    '3' => ['CRITICAL', 'No nodes available in this Virtual Server'],
    '4' => ['UNKNOWN', 'Virtual Server status is notOnThisUnit']
  },
  '9' => {
    'OID' => '.1.3.6.1.4.1.3375.2.2.10.1.2.1.22.',
    '0' => ['WARNING', 'Virtual Server is Disabled'],
    '1' => ['OK', 'Virtual Server is Up and available'],
    '2' => ['CRITICAL', 'Virtual Server is currently not available'],
    '3' => ['CRITICAL', 'Virtual Server is not available'],
    '4' => ['WARNING', 'Virtual Server status is unknown']
  },
  '9.3' => {
    'OID' => '.1.3.6.1.4.1.3375.2.2.10.13.2.1.2.',
    '0' => ['CRITICAL', 'Error'],
    '1' => ['OK', 'Virtual Server is Up and available'],
    '2' => ['CRITICAL', 'Virtual Server is currently not available'],
    '3' => ['CRITICAL', 'Virtual Server is not available'],
    '4' => ['WARNING', 'Virtual Server status is unknown'],
    '5' => ['CRITICAL', 'Unlicensed']
  }
);

my $np = Nagios::Plugin->new(
  usage => "Usage: %s -H <hostname> -C <Community> -S <SW Version>\n"
    . '       -I <VS Name/IP Address> [ -p <VS Port> ]',
  version => $VERSION,
  plugin  => $PROGNAME,
  shortname => uc($PROGNAME),
  blurb => 'Check BigIP Virtual Server status',
  timeout => 10,
);

$np->add_arg(
  spec => 'hostname|H=s',
  help => '-H, --hostname=<hostname>',
  required => 1,
);

$np->add_arg(
  spec => 'community|C=s',
  help => '-C, --community=<Community>',
  required => 1,
);

$np->add_arg(
  spec => 'software|S=s',
  help => "-S, --software=<SW Version> \n"
    . "   The BigIP software version running on the BigIP. This can be:\n"
    . "   4.5\tOlder BigIP models like the 5100 series.\n"
    . "   9\tNewer BigIP LTM like the 6400 series.\n",
  required => 1,
);

$np->add_arg(
  spec => 'ipaddr|I=s',
  help => "-I, --ipaddr=<VS Name/IP Address>\n"
    . "   This is the exact (case-sensitive) Vitrual Server name for version 9 BigIP\n"
    . "   models. On older version 4.5 models, use the Virtual Server IP address.",
  required => 1,
);

$np->add_arg(
  spec => 'port|p=i',
  help => "-p, --port=<VS Port>\n"
    . "   This parameter is required for version 4.5 BigIP and is ignored on version 9\n"
    . "   models.",
  required => 0,
);

$np->getopts;

# Assign, then check args
my $hostname = $np->opts->hostname;
my $software = $np->opts->software;
my $virtualServer = $np->opts->ipaddr;
my $community = $np->opts->community;
my $virtualServerPort = $np->opts->port;

$np->nagios_exit('UNKNOWN', 'Hostname contains invalid characters.')
  if ($hostname =~ /\`|\~|\!|\$|\%|\^|\&|\*|\||\'|\"|\<|\>|\?|\,|\(|\)|\=/);
$np->nagios_exit('UNKNOWN', "Unknown SW version $software.")
  if ($software ne '4.5' && $software ne '9');

if ($software eq '4.5') {
  $np->nagios_exit('UNKNOWN', 'VS IP Address must be an IP address.')
    if ($virtualServer !~ /(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})/);

  $np->nagios_exit('UNKNOWN', "VS IP Address $virtualServer is not a valid IP address.")
    if ($1<0 || $1>255 || $2<0 || $2>255 || $3<0 || $3>255 || $4<0 || $4>255);

  $np->nagios_exit('UNKNOWN', 'Port is required for version 4.5 BigIP.')
    if (!$virtualServerPort);
}

$np->nagios_exit('UNKNOWN', 'Community contains invalid characters.')
  if ($community =~ /\`|\~|\!|\$|\%|\^|\&|\*|\||\'|\"|\<|\>|\?|\,|\(|\)|\=/);


# Just in case of problems, let's not hang Nagios
alarm $np->opts->timeout;

my $oid;
# Get the complete OID for the Virtual Server status.
if ($software eq '4.5') {
  $oid = $bip{$software}{'OID'};
  $oid .= "$virtualServer.$virtualServerPort";
}

if ($software eq '9') {

  # First get the exact version
  my $vercmd = "$snmpcmd -v2c -c $community -m '' -On -Oe $hostname .1.3.6.1.4.1.3375.2.1.4.2.0";
  if ($np->opts->verbose) {
    print STDERR "Getting BigIP Version trough SNMP\n";
    print STDERR "Running command: \"$vercmd\"\n" if ($np->opts->verbose >= 2);
  } else {
    $vercmd .= ' 2>/dev/null';
  }
  my $version=`$vercmd`;
  print STDERR "Command returned: \"$version\"\n" if ($np->opts->verbose >= 3);
  $np->nagios_exit('CRITICAL', 'Could not retrieve information from the BigIP') if ($? != 0);

  my @version=split(/ /,$version);
  $version=$version[3] if (defined($version[3]));

  $version =~ m/(\d+)\.(\d+)\.\d+/;
  print "Got major version $1, minor version $2\n" if ($np->opts->verbose);
  if ($1 == 9 && $2 >= 3) {
    $software = '9.3';
  } elsif ($1 ne '9') {
    $np->nagios_exit('CRITICAL', 'Unknown BigIP LTM version $version');
  }

  $oid = $bip{$software}{'OID'};
  my $vslength = length($virtualServer);
  $virtualServer =~ s/(.)/sprintf('.%u', ord($1))/eg;
  $oid .= $vslength . $virtualServer;
}

my $cmd = "$snmpcmd -v2c -c $community -m '' -On -Oe $hostname $oid";

if ($np->opts->verbose) {
  print STDERR "Getting 'virtualServerStatus' trough SNMP\n";
  print STDERR "Running command: \"$cmd\"\n" if ($np->opts->verbose >= 2);
} else {
  $cmd .= ' 2>/dev/null';
}

my $result=`$cmd`;

print STDERR "Command returned: \"$result\"\n" if ($np->opts->verbose >= 3);

$np->nagios_exit('CRITICAL', 'Could not retrieve information from the BigIP') if ($? != 0);

#Turn off alarm
alarm(0);

my @test=split(/ /,$result);
$result=$test[3] if (defined($test[3]));

$np->nagios_exit('CRITICAL', 'Could not interpret information from the BigIP')
  if ($result !~ /^\d+$/);
my $status=int($result);

# Return the VS status...
$np->nagios_exit(@{$bip{$software}{$status}})
  if (defined($bip{$software}{$status}));

# We should NEVER end up here...
$np->nagios_exit('UNKNOWN', "Virtual Server status $status undefined");


