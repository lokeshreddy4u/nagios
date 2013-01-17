#!/usr/bin/perl  -w

# This script deletes comments older than n days from the monitoring system.

# This script is made available without warranty express or implied.
# Use it at your own risk.

# Note this script does very little checking to make sure what it is doing is sensible - be warned!

# I suggest this script is best run from the nagios user's crontab something like so:

# 13 03 * * * /home/nagios/bin/del_comments -d 90 -s /usr/local/nagios/var/status.dat -c /usr/local/nagios/var/rw/nagios.cmd > /usr/local/nagios/var/log/del_comments.log 2>&1

# Jim Avery, August 2011

use Getopt::Long;
use POSIX qw/strftime/;

my $o_days=        undef;    # no of days to retain
my $o_statusfile=  undef;    # path to the status.dat file
my $o_commandpipe= undef;    # path to the Nagios command pipe
my $entry_time=    undef;    # time of the entry
my $time_now=      undef;    # The time right now
my $time_oldest=   undef;    # The time of the oldest comment we want to retain


sub print_usage {
    print "Usage: $0 -d <days> -s <pathname of status.dat file> -c <pathname of the Nagios command pipe>\n";
}

sub check_options {
  Getopt::Long::Configure ("bundling");
    GetOptions(
    'd:i'   => \$o_days,         'days'    => \$o_days,
    's:s'   => \$o_statusfile,   'statusfile' => \$o_statusfile,
    'c:s'   => \$o_commandpipe,  'commandpipe' => \$o_commandpipe
    );
  if ( ! defined($o_days) ) { 
    print_usage(); exit 1 }
  if ( ! defined($o_statusfile) ) { 
    print_usage(); exit 1 }
  if ( ! defined($o_commandpipe) ) { 
    print_usage(); exit 1 }
}


# Start main body of the script

check_options();

# What is the current date/time?

$time_now= strftime( "%s", localtime(time()) );

# What is the date/time before which we want to delete comments?

$time_oldest= ( $time_now - 60 * 60 * 24 * $o_days ) ;

open(SF, $o_statusfile);

while ($line = <SF>) {
  if ($line =~ /servicecomment/) {
    while ($line = <SF>) {
      if ($line =~ /comment_id/) {
        if($line =~ m/(\d+)/) {
          $comment_id = $1 ;
        }
      }
      if ($line =~ /entry_time/) {
        if ($line =~ m/(\d+)/) {
          $entry_time = $1 ;
          if ($entry_time < $time_oldest) {
            # Write command to the Nagios command pipe
            open(CP, ">>$o_commandpipe");
            print CP "[$time_now] DEL_SVC_COMMENT;$comment_id;$time_now\n";
            close (CP);
          }
        }
      }
    }
  }
}

close SF;

# Now do same as above but for host comments.

open(SF, $o_statusfile);

while ($line = <SF>) {
  if ($line =~ /hostcomment/) {
    while ($line = <SF>) {
      if ($line =~ /comment_id/) {
        if($line =~ m/(\d+)/) {
          $comment_id = $1 ;
        }
      }
      if ($line =~ /entry_time/) {
        if ($line =~ m/(\d+)/) {
          $entry_time = $1 ;
          if ($entry_time < $time_oldest) {
            # Write command to the Nagios command pipe
            open(CP, ">>$o_commandpipe");
            print CP "[$time_now] DEL_HOST_COMMENT;$comment_id;$time_now\n";
            close (CP);
          }
        }
      }
    }
  }
}

close SF;

