#!/usr/bin/ruby

##
## Author:    Andy Walker <andy@fbsdata.com>
## Copyright: Copyright (c) 2012 FBS Datasystems
## License:   GNU General Public License
## Websites:  https://github.com/walkeran/nagios-check_dellwarranty
##            http://exchange.nagios.org/directory/Plugins/Hardware/Server-Hardware/Dell/check_dellwarranty/details
##            https://www.monitoringexchange.org/inventory/Check-Plugins/Hardware/Server-%2528Manufacturer%2529/check_dellwarranty
##
##    This program is free software: you can redistribute it and/or modify
##    it under the terms of the GNU General Public License as published by
##    the Free Software Foundation, either version 3 of the License, or
##    (at your option) any later version.
##
##    This program is distributed in the hope that it will be useful,
##    but WITHOUT ANY WARRANTY; without even the implied warranty of
##    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
##    GNU General Public License for more details.
##
##    You should have received a copy of the GNU General Public License
##    along with this program.  If not, see <http://www.gnu.org/licenses/>.
##

begin
  require 'date'
  require 'optparse'
  require 'soap/wsdlDriver'
rescue Exception => e
  puts "You need the date, optparse, and soap libraries installed."
  puts e.message
  exit 2
end

WSDL_URL = 'http://xserv.dell.com/services/assetservice.asmx?WSDL'
GUID     = '11111111-1111-1111-1111-111111111111'
App      = 'check_dellwarranty.rb'

PLUGIN_VERSION  = '0.4'

Errlevels = { 0 => "OK",
              1 => "WARNING",
              2 => "CRITICAL",
              3 => "UNKNOWN"
            }

options = {}

optparse = OptionParser.new do|opts|
  opts.banner = "Usage: #{App} -H <hostname> | -s <servicetag> [options]"

  options[:hostname] = ""
  opts.on( '-H', '--hostname <hostname>', 'Hostname to get warranty status for. Uses SNMP' ) do |hostname|
    options[:hostname] = hostname
  end

  options[:serial] = ""
  opts.on( '-s', '--servicetag <servicetag>', 'ServiceTag ID to check' ) do |serial|
    options[:serial] = serial
  end

  options[:snmp_comm] = 'public'
  opts.on( '-C', '--community <community>', 'SNMP Community to use when polling for service tag') do |comm|
    options[:snmp_comm] = comm
  end

  options[:snmp_version] = :SNMPv2c
  opts.on( '-v', '--snmpver <snmpver>', 'SNMP Version to use when polling for service tag') do |ver|
    case ver
    when '1'
      options[:snmp_ver] = :SNMPv1
    when '2c'
      options[:snmp_var] = :SNMPv2c
    else
      puts "That SNMP version is not supported. Use 1 or 2c only"
      exit 2
    end
  end

  options[:warn_days] = 90
  opts.on( '-w', '--warning <days>', 'Warning threshold for number of days remaining on contract (Default: 90)' ) do |w|
    options[:warn_days] = w.to_i
  end

  options[:crit_days] = 30
  opts.on( '-c', '--critical <days>', 'Critical threshold for number of days remaining on contract (Default: 30)' ) do |c|
    options[:crit_days] = c.to_i
  end

  options[:verbose] = false
  opts.on( '-v', '--verbose', 'Enable verbose output' ) do |v|
    options[:verbose] = v
  end

  options[:debug] = false
  opts.on( '-d', '--debugging', 'Enable debugging output (Implies -v)' ) do |d|
    options[:debug] = d
  end

  opts.on_tail( '-h', '--help', 'Display this screen' ) do
    puts opts
    exit 2
  end
end

begin
  optparse.parse!
rescue StandardError => e
  puts "Error parsing command line arguments."
  puts e.message
  puts optparse
  exit 2
end

class ServiceLevel
  attr_accessor :serviceLevelDescription, :serviceLevelCode

  def endDate
    @endDate
  end

  def endDate=(endDate)
    if endDate.is_a?(DateTime)
      @endDate = endDate
    elsif endDate.is_a?(String)
      @endDate = DateTime.parse(endDate)
    else
      puts "endDate doesn't accept " + endDate.class.to_s + " types!"
      exit 2
    end
  end

  def <=>(other)
    self.endDate <=> other.endDate
  end

  def to_s
    @serviceLevelDescription + ", " + @serviceLevelCode + ", " + @endDate.strftime('%Y/%m/%d')
  end
end

class DellEntitlements
  def initialize
    @entitlements = Array.new
    @servicelevels = Hash.new
  end

  def servicelevels
    @servicelevels
  end

  def entitlements
    @entitlements
  end

  def add(ent)
    @entitlements.push ent

    # Gloss over Expired entitlements. Should we be alerting on
    #  these? Maybe... maybe not... will have to wait for input
    if ent.entitlementType == "Expired"
      return
    end

    slkey = ''

    if ent.serviceLevelCode == nil
      # This is a somewhat special case, where Dell doesn't supply service
      #  level codes or descriptions. We should keep track of all of these
      #  service levels separately, so we'll calculate a new key for it

      # TODO: We should probably check for key collisions at some point. I
      #  don't foresee this as beinga problem, but you never know!
      slkey = @servicelevels.length.to_s
    elsif @servicelevels[ent.serviceLevelCode] != nil
      # In this case, Dell has given us a service level code, and our
      #  hash is already tracking this type. Let's just extend the endDate
      #  if it goes beyond the one that's already recorded
      @servicelevels[ent.serviceLevelCode].endDate = [ @servicelevels[ent.serviceLevelCode].endDate, ent.endDate ].max

      # And then bail out...
      return
    else
      # Otherwise, we have a decent service level code that we can use as a key
      slkey = ent.serviceLevelCode
    end

    # If we get this far, we should add the new service level using the key we've come up with
    servicelevel = ServiceLevel.new
    servicelevel.endDate = ent.endDate
    servicelevel.serviceLevelDescription = ent.serviceLevelDescription if ent.serviceLevelDescription
    servicelevel.serviceLevelCode = ent.serviceLevelCode if ent.serviceLevelDescription

    @servicelevels[slkey] = servicelevel
  end
end

class DellEntitlement < ServiceLevel
  attr_accessor :entitlementType,
    :provider

  def initialize(args)
    @entitlementType         = args[:type]
    @serviceLevelDescription = args[:desc] if args[:desc]
    @provider                = args[:prov] if args[:prov]
    @serviceLevelCode        = args[:code] if args[:code]
    self.startDate           = args[:startDate]
    self.endDate             = args[:endDate]
  end

  def startDate
    @startDate
  end

  def startDate=(startDate)
    if startDate.is_a?(DateTime)
      @startDate = startDate
    elsif startDate.is_a?(String)
      @startDate = DateTime.parse(startDate)
    else
      puts "startDate doesn't accept " + startDate.class.to_s + " types!"
      exit 2
    end
  end
end

def suppress_warning
  back = $VERBOSE
  $VERBOSE = nil
  begin
    yield
  ensure
    $VERBOSE = back
  end
end

def get_snmp_serial ( args )
  begin
    require 'rubygems'
    require 'snmp'
  rescue Exception => e
    puts "You need the snmp gem installed."
    puts e.message
    exit 2
  end

  serial = ''
  SNMP::Manager.open(:host => args[:hostname], :community => args[:community], :version => args[:version]) do |manager|
    val = manager.get_value('1.3.6.1.4.1.674.10892.1.300.10.1.11.1')
    serial = val.split[0]
  end

  serial
end

def get_dell_warranty(serial)
  ents = DellEntitlements.new

  driver = suppress_warning { SOAP::WSDLDriverFactory.new(WSDL_URL).create_rpc_driver }
  result = driver.GetAssetInformation(:guid => GUID, :applicationName => App, :serviceTags => serial)

  result.getAssetInformationResult.asset.entitlements.entitlementData.each do | ent | 
    entargs = Hash.new

    entargs[:type]      = ent.entitlementType
    entargs[:startDate] = ent.startDate
    entargs[:endDate]   = ent.endDate
    entargs[:prov] = ent.provider                if defined? ent.provider
    entargs[:desc] = ent.serviceLevelDescription if defined? ent.serviceLevelDescription
    entargs[:code] = ent.serviceLevelCode        if defined? ent.serviceLevelCode

    ents.add DellEntitlement.new(entargs)
  end

  ents
end

def expire_message(errlevel, daysleft, desc)
  if desc
    "\n#{Errlevels[errlevel]}: '#{desc}' support ends in #{daysleft} days"
  else
    "\n#{Errlevels[errlevel]}: A support contract ends in #{daysleft} days"
  end
end

entitlements = DellEntitlements.new
serial       = ''
now          = DateTime.now
errlevel     = 0
count        = 0
expiring     = 0
nextexpire   = nil
outmsg       = ''

if options[:debug]
  options[:verbose] = true
end

if options[:crit_days] <= 0
  puts "ERROR: -w and -c must be positive integers"
  exit 2
end

if options[:crit_days] > options[:warn_days]
  puts "ERROR: -w cannot be less than -c"
  exit 2
end

if options[:hostname].length > 0
  puts "Hostname: #{options[:hostname]}" if options[:debug]
  serial = get_snmp_serial( :hostname => options[:hostname],
                            :community => options[:snmp_comm],
                            :version => options[:snmp_ver] )
elsif options[:serial].length > 0
  serial = options[:serial]
else
  puts "ERROR: Must supply either a hostname or servicetag!"
  puts optparse
  exit 2
end

puts "Serial: #{serial}" if options[:debug]
entitlements = get_dell_warranty(serial)

entitlements.servicelevels.sort_by { |k,v| v }.each do |k,sl|
  endDate  = sl.endDate
  desc     = sl.serviceLevelDescription
  daysleft = (endDate - now).round
  count += 1

  if daysleft >= 0
    nextexpire = (nextexpire == nil) ? daysleft : [nextexpire,daysleft].min
  end

  if daysleft <= options[:crit_days]
    outmsg += expire_message(2, daysleft, desc) if options[:verbose]
    expiring += 1
    errlevel = [ errlevel, 2 ].max
  elsif daysleft <= options[:warn_days]
    outmsg += expire_message(1, daysleft, desc) if options[:verbose]
    expiring += 1
    errlevel = [ errlevel, 1 ].max
  else
    outmsg += expire_message(0, daysleft, desc) if options[:verbose]
  end
end

puts "#{Errlevels[errlevel]}: #{expiring} of #{count} service contracts are expiring (Next: #{nextexpire} days)#{outmsg}"

exit errlevel

