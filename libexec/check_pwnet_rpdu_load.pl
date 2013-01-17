#!/usr/bin/perl -w

# check_pwnet_rpdu_load Nagios Plugin
# Checks the bank load on a PDU supporting APC PowerNet MIB
# Type check_pwnet_rpdu_load --help for getting more info and examples.
#
# This nagios plugin is free software, and comes with ABSOLUTELY NO WARRANTY.
# It may be used, redistributed and/or modified under the terms of the GNU 
# General Public Licence (see http://www.fsf.org/licensing/licenses/gpl.txt).


# MODULE DECLARATION

use strict;

use Nagios::Plugin;
use Net::SNMP qw(SNMP_VERSION_2C);



# FUNCTION DECLARATION

sub CreateNagiosManager ();
sub CheckArguments ();
sub TestHost ();
sub PerformCheck ();


# CONSTANT DEFINITION

use constant PWNET_RPDU => '.1.3.6.1.4.1.318.1.1.12';

use constant MODE_TEST => 1;
use constant MODE_CHECK => 2;

use constant NAME => 	'check_pwnet_rpdu_load';
use constant VERSION => '0.1b';
use constant USAGE => 	"Usage:\n".
								"check_pwnet_rpdu_load -H <hostname>\n" .
								"\t\t[-C <SNMP Community>] [-e <SNMP Version>] [-P <SNMP port>] [-t <SNMP timeout>]\n" .
								"\t\t[-b <bank id list>]\n" .
								"\t\t[-w <per-bank threshold list> -c <per-bank threshold list>]\n" .
								"\t\t[-V <version>]\n";
use constant BLURB => 	"This plugin checks the bank load on a PDU supporting APC Powernet MIB.";
use constant LICENSE => "This nagios plugin is free software, and comes with ABSOLUTELY NO WARRANTY\n".
								"It may be used, redistributed and/or modified under the terms of the GNU\n".
								"General Public Licence (see http://www.fsf.org/licensing/licenses/gpl.txt).\n";
use constant EXAMPLE => "\n\n".
								"Examples:\n".
								"\n".
								"check_pwnet_rpdu_load -H 192.168.0.1\n".
								"\n".
								"If available, displays info of the PDU with address 192.168.1.1\n".
								"using SNMP protocol version 1 and 'public' as community\n".
								"(useful for checking compatibility and displaying bank data)\n".
								"\n".
								"check_pwnet_rpdu_load -H 192.168.0.1 -b 1,2 -w n,12 -c 16,o\n".
								"\n".
								"Checks bank 1 & 2 load, in amperes, on a host with address 192.168.0.1\n".
								"using SNMP protocol version 1 and 'public' as community.\n".
								"As PDU manages bank status based on its load (near-overload or overload)\n".
								"plugin allows checking thresholds both stating a load status or a load level.\n".
								"In the example, plugin returns WARNING if bank 1 gets near-overload (n) status\n".
								"and/or bank 2 load raises 12 amperes, and plugin returns CRITICAL if bank 1\n".
								"raises 16 amperes and/or bank 2 gets 'overload' (o) status.\n".
								"In other case it returns OK if check has been performed or UNKNOWN.";


# VARIABLE DEFINITION

my $Nagios;
my $Error;
my $PluginMode;
my $PluginReturnValue, my $PluginOutput;


# MAIN FUNCTION

# Get command line arguments
$Nagios = &CreateNagiosManager(USAGE, VERSION, BLURB, LICENSE, NAME, EXAMPLE);
eval {$Nagios->getopts};

if (!$@) {
	# Command line parsed
	if (&CheckArguments($Nagios, $Error, $PluginMode)) {
		# Argument checking passed
		if ($PluginMode == MODE_TEST) {
			&TestHost($Nagios, $PluginOutput);
			$PluginReturnValue = UNKNOWN;
			$PluginOutput = "TEST MODE\n\n" . $PluginOutput;
		}
		else {
			$PluginReturnValue = &PerformCheck($Nagios, $PluginOutput)
		}
	}
	else {
		# Error checking arguments
		$PluginOutput = $Error;
		$PluginReturnValue = UNKNOWN;
	}
	$Nagios->nagios_exit($PluginReturnValue,$PluginOutput);
}
else {
	# Error parsing command line
	$Nagios->nagios_exit(UNKNOWN,$@);
}

		
	
# FUNCTION DEFINITIONS

# Creates and configures a Nagios plugin object
# Input: strings (usage, version, blurb, license, name and example) to configure argument parsing functionality
# Return value: reference to a Nagios plugin object

sub CreateNagiosManager() {
	# Create GetOpt object
	my $Nagios = Nagios::Plugin->new(usage => $_[0], version =>  $_[1], blurb =>  $_[2], license =>  $_[3], plugin =>  $_[4], extra =>  $_[5]);
	
	# Add argument hostname
	$Nagios->add_arg(spec => 'hostname|H=s',
				help => 'SNMP agent hostname or IP address',
				required => 1);				
	
	# Add argument bank list
	$Nagios->add_arg(spec => 'bank|b=s',
				help => 'Comma separated bank number list',
				required => 0);
					
	# Add argument community
	$Nagios->add_arg(spec => 'community|C=s',
				help => 'SNMP agent community (default: public)',
				default => 'public',
				required => 0);				
	# Add argument version
	$Nagios->add_arg(spec => 'snmpver|E=s',
				help => 'SNMP protocol version (default: 1)',
				default => '1',
				required => 0);				
	# Add argument port
	$Nagios->add_arg(spec => 'port|P=i',
				help => 'SNMP agent port (default: 161)',
				default => 161,
				required => 0);

	# Add argument warning
	$Nagios->add_arg(spec => 'warning|w=s',
				help => "Comma separated bank threshold list. ".
						"Valid thesholds are bank load status (n=near overload,o=overload) ".
						"or bank load numeric values.",
				required => 0);
	# Add argument critical
	$Nagios->add_arg(spec => 'critical|c=s',
				help => "Comma separated bank threshold list. ".
						"Valid thesholds are bank load status (n=near overload,o=overload) ".
						"or bank load numeric values.",
				required => 0);
								
	# Return value
	return $Nagios;
}


# Checks argument values and sets some default values
# Input: Nagios Plugin object
# Output: Error description string, Plugin mode
# Return value: True if arguments ok, false if not

sub CheckArguments() {
	my $Nagios = $_[0];
	
	# Check if agent port number is > 0
	if ( $Nagios->opts->port <= 0 ) {
		$_[1] = "Invalid SNMP agent port: must be greater than zero";
		return 0;
	}
	
	# Check plugin test mode
	if (defined $Nagios->opts->bank && defined $Nagios->opts->warning && defined $Nagios->opts->critical) {
		$_[2] = MODE_CHECK;
		
		# Check bank list
		if ( $Nagios->opts->bank !~ /^(\d+,)*\d+$/) {
			$_[1] = "Invalid bank number list: must be a comma separated bank-id list";
			return 0;
		}	
		
		# Check warning value list
		if ( $Nagios->opts->warning !~ /^((\d+(.\d+)?|[no]),)*(\d+(.\d+)?|[no])$/) {
			$_[1] = "Invalid warning threshold list: each bank threshold must be a load status (n,o) or a load value";
			return 0;
		}
	
		# Check critical value list
		if ( $Nagios->opts->critical !~ /^((\d+(.\d+)?|[no]),)*(\d+(.\d+)?|[no])$/) {
			$_[1] = "Invalid critical threshold list: each bank threshold must be a load status (n,o) or a load value";
			return 0;
		}
		
		# Check that both three lists have the same number of items
		my @BankList = split(/,/, $Nagios->opts->bank);
		my @WarningList = split(/,/, $Nagios->opts->warning);
		my @CriticalList = split(/,/, $Nagios->opts->critical);
		if (@BankList != @WarningList) {
			$_[1] = "Invalid warning threshold list: item number different to bank list item number";
			return 0;
		}
		if (@BankList != @CriticalList) {
			$_[1] = "Invalid critical threshold list: item number different to bank list item number";
			return 0;
		}
	}
	elsif ( !defined $Nagios->opts->bank && !defined $Nagios->opts->warning && !defined $Nagios->opts->critical){
		$_[2] = MODE_TEST;
	}
	else {
		$_[1] = "Invalid argument set";
		return 0;		
	}
	
	return 1;
}


# Checks if host supports PowerNet MIB PDU related info.
# If true, it returns info about PDU and banks
# Input: Nagios Plugin object
# Output: Test output string
# Return value: 1 if test passed, 0 if not.

sub TestHost() {
	my $OID_rPDUIdentName = PWNET_RPDU . '.1.1.0';
	my $OID_rPDUIdentModelNumber = PWNET_RPDU . '.1.5.0';
	my $OID_rPDUIdentDeviceNumOutlets = PWNET_RPDU . '.1.8.0';
	my $OID_rPDUIdentDeviceNumBreakers = PWNET_RPDU . '.1.10.0';
	
	my $OID_rPDULoadDevBankNumber =  PWNET_RPDU . '.2.1.6.1.2';
	my $OID_rPDULoadDevBankMaxLoad =  PWNET_RPDU . '.2.1.6.1.3';
	
	my $Nagios = $_[0];
	
	my $SNMPSession;
	my $SNMPError;
	my @RequestData;
	my $RequestResult;
	
	# Start new SNMP session
	($SNMPSession, $SNMPError) = Net::SNMP->session(-hostname => $Nagios->opts->hostname, -community => $Nagios->opts->community, -version => $Nagios->opts->snmpver, -port => $Nagios->opts->port, -timeout => $Nagios->opts->timeout);
	
	if (defined($SNMPSession)) {
		# Define data to recover: PDU identification data
		@RequestData = ($OID_rPDUIdentName, $OID_rPDUIdentModelNumber, $OID_rPDUIdentDeviceNumOutlets, $OID_rPDUIdentDeviceNumBreakers);

		# Perform SNMP request
		$RequestResult = $SNMPSession->get_request(-varbindlist => \@RequestData);
		$SNMPError = $SNMPSession->error();
		
		if (defined $RequestResult) {
			$_[1] = "PDU DATA\n".
					"Model: $RequestResult->{$OID_rPDUIdentModelNumber}\n".
					"Name: $RequestResult->{$OID_rPDUIdentName}\n".
					"Breakers (banks): $RequestResult->{$OID_rPDUIdentDeviceNumBreakers}\n".
					"Outlets: $RequestResult->{$OID_rPDUIdentDeviceNumOutlets}\n\n";
					
			# Define data to recover: Bank data
			@RequestData = ($OID_rPDULoadDevBankNumber, $OID_rPDULoadDevBankMaxLoad);
			
			# Perform SNMP request
			$RequestResult = $SNMPSession->get_entries(-columns => \@RequestData);
			$SNMPError = $SNMPSession->error();
		
			if (defined $RequestResult) {
				# Print bank data and return success;
				$_[1] .= "BANK DATA";
				for (my $i = 1; $i <= (keys %$RequestResult)/2; $i++) {
					$_[1] .= "\nBank #" . $RequestResult->{"$OID_rPDULoadDevBankNumber.$i"} . " max. load: " . $RequestResult->{"$OID_rPDULoadDevBankMaxLoad.$i"} . "A.";
				}
				return 1;
			}
			else {
				$_[1] = "Error '$SNMPError' requesting PDU bank data ".
						"from agent $Nagios->{opts}->{hostname}:$Nagios->{opts}->{port} ".
						"using protocol $Nagios->{opts}->{snmpver} ". 
						"and community string **hidden for security**"; # '$Nagios->{opts}->{community}'";
				return 0;
			}
		}
		else {
			$_[1] = "Error '$SNMPError' requesting PDU identification data ".
					"from agent $Nagios->{opts}->{hostname}:$Nagios->{opts}->{port} ".
					"using protocol $Nagios->{opts}->{snmpver} ". 
					"and community string **hidden for security**"; # '$Nagios->{opts}->{community}'";
			return 0;
		}
		
		$SNMPSession->close();
	}
	else {
		# Error starting SNMP session;
		$PluginOutput = "Error '$SNMPError' starting session";
		
		return 0;	
	}
}


# Performs whole check: 
# Input: Nagios Plugin object
# Output: Plugin output string
# Return value: Plugin return value

sub PerformCheck() {
	my $OID_rPDUIdentName = PWNET_RPDU . '.1.1.0';
	my $OID_rPDUIdentDeviceRating = PWNET_RPDU . '.1.7.0';
	my $OID_rPDULoadDevBankMaxLoad = PWNET_RPDU . '.2.1.6.1.3';
	my $OID_rPDULoadStatusLoad = PWNET_RPDU . '.2.3.1.1.2';
	my $OID_rPDULoadStatusBankNumber = PWNET_RPDU . '.2.3.1.1.5';
	my $OID_rPDULoadBankConfigNearOverloadThreshold = PWNET_RPDU . '.2.4.1.1.3';
	my $OID_rPDULoadBankConfigOverloadThreshold = PWNET_RPDU . '.2.4.1.1.4';
	
	my $Nagios = $_[0];
	
	my $SNMPSession;
	my $SNMPError;
	my @RequestColumns;
	my $RequestResult;
	
	my $PDUData;
	my $PDUBankTable;
	my $PDULoadStatusTable;
	my $PDULoadConfigTable;
	
	my $BankLoadValue;
	my $WarningThresholdValue;
	my $CriticalThresholdValue;	
	my $Magnitude = 'A';
	
	my @CheckedBanks;
	my @BankWarningThresholds;
	my @BankCriticalThresholds;
	
	my $PluginOutput;
	my $PluginReturnValue = UNKNOWN;
	my $PerformanceData;
	
	
	# Start new SNMP session
	($SNMPSession, $SNMPError) = Net::SNMP->session(-hostname => $Nagios->opts->hostname, -community => $Nagios->opts->community, -version => $Nagios->opts->snmpver, -port => $Nagios->opts->port, -timeout => $Nagios->opts->timeout);
	if (defined($SNMPSession)) {
		#Get target banks and check thresholds	
		push (@CheckedBanks, $Nagios->opts->bank) if scalar(@CheckedBanks = split(/,/, $Nagios->opts->bank)) == 0;
		push (@BankWarningThresholds, $Nagios->opts->warning) if scalar(@BankWarningThresholds = split(/,/, $Nagios->opts->warning)) == 0;
		push (@BankCriticalThresholds, $Nagios->opts->critical) if scalar(@BankCriticalThresholds = split(/,/, $Nagios->opts->critical)) == 0;
		
		# Perform SNMP requests
		$PDUData = $SNMPSession->get_request(-varbindlist => [$OID_rPDUIdentName, $OID_rPDUIdentDeviceRating]);
		if ($SNMPError eq '') {
			$PDUBankTable = $SNMPSession->get_entries(-columns => [$OID_rPDULoadDevBankMaxLoad]);
			$SNMPError = $SNMPSession->error();
		}
		$SNMPError = $SNMPSession->error();
		if ($SNMPError eq '') {
			$PDULoadStatusTable = $SNMPSession->get_entries(-columns => [$OID_rPDULoadStatusLoad, $OID_rPDULoadStatusBankNumber]);
			$SNMPError = $SNMPSession->error();
		}
		if ($SNMPError eq '') {
			$PDULoadConfigTable = $SNMPSession->get_entries(-columns => [$OID_rPDULoadBankConfigNearOverloadThreshold, $OID_rPDULoadBankConfigOverloadThreshold]);
			$SNMPError = $SNMPSession->error();
		}
		
		if ($SNMPError eq '') {
			# Data successfully fetched
			# Check each bank load data in the Bank Load table comparing its value with user thresholds 
			# This table is linked to the master Bank table by the rPDULoadStatusBankNumber OID and NOT by the rPDULoadStatusIndex field
			
			# Set default plugin result and plugin output heading
			$PluginReturnValue = OK;
			$PluginOutput = "PDU '$PDUData->{$OID_rPDUIdentName}' ";
			
			for (my $CheckedBankItem = 0; $CheckedBankItem < @CheckedBanks && $PluginReturnValue != UNKNOWN; $CheckedBankItem++) {
				my $CheckedBankItemNumber = $CheckedBanks[$CheckedBankItem];

				# Search bank load register
				my $BankLoadTableItem=1;
				while ($PDULoadStatusTable->{$OID_rPDULoadStatusBankNumber.".$BankLoadTableItem"} != $CheckedBankItemNumber && $BankLoadTableItem < keys(%$PDULoadStatusTable)/2) {
					$BankLoadTableItem++;
				}
				
				if ($PDULoadStatusTable->{"$OID_rPDULoadStatusBankNumber.$BankLoadTableItem"} == $CheckedBankItemNumber) {
					# Register located
					# Now compare bank load value with user thresholds
					# If threshold is a load state (i.e. a defined near-overload or overload value)
					# get defined threshold bank load value in table PDULoadConfig
					
					$BankLoadValue = sprintf("%.1f", $PDULoadStatusTable->{"$OID_rPDULoadStatusLoad.$BankLoadTableItem"} / 10);
					
					# Check critical threshold
					if ($BankCriticalThresholds[$CheckedBankItem] eq 'n') {
						# Threshold set as load state near-overload
						$CriticalThresholdValue = sprintf("%.1f", $PDULoadConfigTable->{"$OID_rPDULoadBankConfigNearOverloadThreshold.$CheckedBankItemNumber"});
						if ( $BankLoadValue >= $CriticalThresholdValue ) {
							$PluginReturnValue = CRITICAL;
							$PluginOutput .= "bank #$CheckedBankItemNumber load = $BankLoadValue$Magnitude (critical threshold set to near-overload = $CriticalThresholdValue$Magnitude); ";
						}
					}
					elsif ($BankCriticalThresholds[$CheckedBankItem] eq 'o') {
						# Threshold set as load state overload
						$CriticalThresholdValue = sprintf("%.1f", $PDULoadConfigTable->{"$OID_rPDULoadBankConfigOverloadThreshold.$CheckedBankItemNumber"});
						if ( $BankLoadValue >= $CriticalThresholdValue ) {
							$PluginReturnValue = CRITICAL;
							$PluginOutput .= "bank #$CheckedBankItemNumber load = $BankLoadValue$Magnitude (critical threshold set to overload = $CriticalThresholdValue$Magnitude); ";
						}
					}
					else {
						# Threshold set as load value
						$CriticalThresholdValue = sprintf("%.1f", $BankCriticalThresholds[$CheckedBankItem]);
						if ( $BankLoadValue >= $CriticalThresholdValue ) {
							$PluginReturnValue = CRITICAL;
							$PluginOutput .= "bank #$CheckedBankItemNumber load = $BankLoadValue$Magnitude (critical threshold set to $CriticalThresholdValue$Magnitude); ";
						}						
					}
					
					#Check warning threshold (if no critical threshold has been raised)		
					if ($BankWarningThresholds[$CheckedBankItem] eq 'n') {
						# Threshold set as load state near-overload
						$WarningThresholdValue = sprintf("%.1f", $PDULoadConfigTable->{"$OID_rPDULoadBankConfigNearOverloadThreshold.$CheckedBankItemNumber"});
						if ( $PluginReturnValue != CRITICAL && $BankLoadValue >= $WarningThresholdValue ) {
							$PluginReturnValue = WARNING;
							$PluginOutput .= "bank #$CheckedBankItemNumber load = $BankLoadValue$Magnitude (warning threshold set to near-overload = $WarningThresholdValue$Magnitude); ";
						}
					}
					elsif ($BankWarningThresholds[$CheckedBankItem] eq 'o') {
						# Threshold set as load state overload
						$WarningThresholdValue = sprintf("%.1f", $PDULoadConfigTable->{"$OID_rPDULoadBankConfigOverloadThreshold.$CheckedBankItemNumber"});
						if ( $PluginReturnValue != CRITICAL && $BankLoadValue >= $WarningThresholdValue ) {
							$PluginReturnValue = WARNING;
							$PluginOutput .= "bank #$CheckedBankItemNumber load = $BankLoadValue$Magnitude (warning threshold set to overload = $WarningThresholdValue$Magnitude); ";
						}
					}
					else {
						# Threshold set as load value
						$WarningThresholdValue = sprintf("%.1f", $BankWarningThresholds[$CheckedBankItem]);
						if ( $PluginReturnValue != CRITICAL && $BankLoadValue >= $WarningThresholdValue ) {
							$PluginReturnValue = WARNING;
							$PluginOutput .= "bank #$CheckedBankItemNumber load = $BankLoadValue$Magnitude (warning threshold set to $WarningThresholdValue$Magnitude); ";
						}						
					}
					
					# If no threshold raised, compose OK plugin output
					if ($PluginReturnValue == OK) {
						$PluginOutput .= "bank #$CheckedBankItemNumber load = $BankLoadValue$Magnitude; "
					}
					
					# Set performance data (<Label>=<Value><Magnitude>;<warning>;<critical>;<minimum>;<maximum>)
					$PerformanceData .= 'PDUBank' . $CheckedBankItemNumber . "Load=$BankLoadValue$Magnitude;$WarningThresholdValue;$CriticalThresholdValue;";
					
					if ( $CheckedBankItemNumber == 0 ) {
						# Bank 0 represents the sum of all banks, ie, the whole PDU
						# Max. rating retrieved from PDU specs
						$PerformanceData .= '0;' . $PDUData->{$OID_rPDUIdentDeviceRating} . ' ';
					}
					else {
						# Max. rating retrieved from bank table
						$PerformanceData .= '0;' . $PDUBankTable->{"$OID_rPDULoadDevBankMaxLoad.$CheckedBankItemNumber"} . ' ';
					}						
				}
				else {
					# Bank load register not found: No bank status info located
					$PluginOutput = "No status info located for bank #$CheckedBankItem";
					$PluginReturnValue = UNKNOWN;
				}
			}
			
			# All target banks processed (or any bank data not found)
			# Finish composing plugin output string
			if ($PluginReturnValue != UNKNOWN) {
				chop($PerformanceData);
				$PluginOutput .= '| ' . $PerformanceData;
			}
			
			$SNMPSession->close();
		}
		else {
			$PluginOutput = "Error '$SNMPError' requesting PDU bank data ".
							"from agent $Nagios->{opts}->{hostname}:$Nagios->{opts}->{port} ".
							"using protocol $Nagios->{opts}->{snmpver} ". 
							"and community string **hidden for security**"; # '$Nagios->{opts}->{community}'";		
		}
	}	
	else {
		# Error starting SNMP session;
		$PluginOutput = "Error '$SNMPError' starting session";
	}
	
	#Return result
	$_[1] = $PluginOutput;
	return $PluginReturnValue;
}