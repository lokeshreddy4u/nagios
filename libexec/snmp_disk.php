#!/usr/bin/php -q
<?php

// Uses SNMP to check the given partition on a remote server
//   Optional config file overrides cmdline thresholds
//
// Aaron M. Segura, October 04, 2006 -- aaron.segura@gmail.com
//

define("VERSION", "0.1");
define("VERDATE", "October 04, 2006");
define("SNMP_RETRIES", "3");
define("SNMP_TIMEOUT", "10000000");

function usage ( $msg = NULL )
{
	print(basename($_SERVER["argv"][0]) ." v". VERSION ." (". VERDATE .") by Aaron M. Segura\n");
	print("Usage: ". basename($_SERVER["argv"][0]) ." -H <host> -n <community> -p <partition> -w <warning> -c <critical> [-f <file>]\n");
	print("\t-H\tHost to be checked\n\t-n\tSNMP Community Name\n\t-p\tPartition to be checked (Must match exactly)\n");
	print("\t-w\tPercent used warning threshold\n\t-c\tPercent used critical threshold\n");
	print("\t-f\tOptional Config file\n");

	if ( strlen($msg) )
		print("\n*** $msg\n\n");

	exit();
}

function parse_config( $file )
{
	$lines = file($file);

	if ( count($lines) > 0 )
	{
		foreach ( $lines as $line )
		{
			$parts = explode(":", $line);

			if ( ! ( ereg("^#", $parts[0]) || ereg("^[[:space:]]*$", $parts[0]) ) )
			{
				if ( ereg("^$", $parts[1]) )
				{
					$config[$parts[0]]["warning"] = $parts[2];
					$config[$parts[0]]["critical"] = $parts[3];
				}
				else
				{
					if ( ! @array_key_exists($parts[1], $config[$parts[0]]) )
					{
						$config[$parts[0]][$parts[1]]["warning"] = $parts[2];
						$config[$parts[0]][$parts[1]]["critical"] = $parts[3];
					}
				}
			}
		}
	}
	return($config);
}

	// main()
	$opts = getopt("H:n:p:w:c:f:");

	foreach($opts as $opt => $arg)
	{
		switch($opt)
		{
			case "H":
				$host = $arg;
			break;

			case "n":
				$community = $arg;
			break;

			case "p":
				$partition = $arg;
			break;

			case "w":
				if ( ereg("^[0-9]{1,3}$", $arg) )
					$warning = $arg;
				else
					usage("Warning threshold must be between 0 and 100 (percent)");

				if ( isset($critical) && ($critical < $warning) )
					usage("Warning threshold cannot be more than Critical threshold");
			break;

			case "c":
				if ( ereg("^[0-9]{1,3}$", $arg) )
					$critical = $arg;
				else
					usage("Critical threshold must be between 0 and 100 (percent)");
	
				if ( isset($warning) && ($critical < $warning) )
					usage("Critical threshold cannot be less than Warning threshold");
			break;

			case "f":
				if ( file_exists($arg) )
					$config = parse_config($arg);
				else
					usage("Even though config file is optional, if you specify it, the file MUST exist.");
			break;
		}
	}

	// Override cmdline vars if config file specified
	if ( isset($config) )
	{
		if ( ! isset($config) )
			usage("Invalid config file.");

		if ( @array_key_exists("warning", $config[$host]) )
			$warning = $config[$host]["warning"];

		if ( @array_key_exists("warning", $config[$host][$partition]) )
			$warning = $config[$host][$partition]["warning"];

		if ( @array_key_exists("critical", $config[$host]) )
			$critical = $config[$host]["critical"];

		if ( @array_key_exists("critical", $config[$host][$partition]) )
			$critical = $config[$host][$partition]["critical"];
	}

	if ( ! isset($host) )
		usage("Must set Host (-H)");
	
	if ( ! isset($community) )
		usage("Must set Community (-n)");

	if ( ! isset($partition) )
		usage("Must set partition (-p)");

	if ( ! isset($warning) )
		usage("Must set warning threshold (-w)");

	if ( ! isset($critical) )
		usage("Must set critical threshold (-c)");

	snmp_set_quick_print(1);

	$hrStorageDescr = @snmprealwalk($host, $community, "hrStorageDescr", SNMP_TIMEOUT, SNMP_RETRIES);

	if ( count($hrStorageDescr) == 1 )
	{
		print("Unable to query server $host\n");
		exit(1);
	}

	foreach ( $hrStorageDescr as $oid => $val )
	{
		if ( ereg("^$partition$", $val) )
			$index = substr($oid, strrpos($oid, ".")+1);

	}

	if ( ! isset($index) )
	{
		print("$partition isn't mounted on $host | used=\n");
		exit(1);
	}

	$used = @snmpget($host, $community, "hrStorageUsed.$index", SNMP_TIMEOUT, SNMP_RETRIES);	
	$total = @snmpget($host, $community, "hrStorageSize.$index", SNMP_TIMEOUT, SNMP_RETRIES);

	if ( ! ereg("^[0-9]+$", $used) )
	{
		print("Unable to determine used space due to failed snmp query | used=\n");
		exit(1);
	}

	if ( ! ereg("^[0-9]+$", $total) )
	{
		print("Unable to determine size due to failed snmp query | used=\n");
		exit(1);
	}

	$pct_used = round(($used / $total)*100, 2);

	if ( $pct_used >= $critical )
	{
		print("DISK CRITICAL - $partition $pct_used% used | used=$pct_used\n");
		exit(2);
	}
	else
		if ( $pct_used >= $warning )
		{
			print("DISK WARNING - $partition $pct_used% used | used=$pct_used\n");
			exit(1);
		}
		else
			print("DISK OK - $partition $pct_used% used | used=$pct_used\n");

?>
