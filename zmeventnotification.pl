#!/usr/bin/perl  -T
#
# ==========================================================================
#
# THIS SCRIPT MUST BE RUN WITH SUDO OR STARTED VIA ZMDC.PL
#
# ZoneMinder Realtime Notification System
#
# A  light weight event notification daemon
# Uses shared memory to detect new events (polls SHM)
# Also opens a websocket connection at a configurable port
# so events can be reported
# Any client can connect to this web socket and handle it further
# for example, send it out via APNS/GCM or any other mechanism
#
# This is a much  faster and low overhead method compared to zmfilter
# as there is no DB overhead nor SQL searches for event matches

# ~ PP
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
# ==========================================================================

use strict;
use bytes;

# ==========================================================================
#
# Starting v1.0, configuration has moved to a separate file, please make sure
# you see README
#
# Starting v0.95, I've moved to FCM which means I no longer need to maintain
# my own push server. Plus this uses HTTP which is the new recommended
# way. Note that 0.95 will only work with zmNinja 1.2.510 and beyond
# Conversely, old versions of the event server will NOT work with zmNinja
# 1.2.510 and beyond, so make sure you upgrade both
#
# ==========================================================================


my $app_version="1.6";

# ==========================================================================
#
# These are app defaults
# Note that you  really should not have to to change these values. 
# It is better you change them inside the ini file.
# These values are used ONLY if the server cannot find its ini file
# The only one you may want to change is DEFAULT_CONFIG_FILE to point
# to your custom ini file if you don't use --config. The rest should
# go into that config file.
# ==========================================================================

use constant DEFAULT_CONFIG_FILE => "/etc/zmeventnotification.ini";

use constant DEFAULT_PORT => 9000;
use constant DEFAULT_ADDRESS => '[::]';
use constant DEFAULT_AUTH_ENABLE => 1;
use constant DEFAULT_AUTH_TIMEOUT => 20;
use constant DEFAULT_FCM_ENABLE => 1;
use constant DEFAULT_MQTT_ENABLE => 0;
use constant DEFAULT_MQTT_SERVER => '127.0.0.1';
use constant DEFAULT_FCM_TOKEN_FILE => '/etc/private/tokens.txt';
use constant DEFAULT_SSL_ENABLE => 1;

use constant DEFAULT_CUSTOMIZE_VERBOSE => 0;
use constant DEFAULT_CUSTOMIZE_EVENT_CHECK_INTERVAL => 5;
use constant DEFAULT_CUSTOMIZE_MONITOR_RELOAD_INTERVAL => 300;
use constant DEFAULT_CUSTOMIZE_READ_ALARM_CAUSE => 0;
use constant DEFAULT_CUSTOMIZE_TAG_ALARM_EVENT_ID => 0;
use constant DEFAULT_CUSTOMIZE_USE_CUSTOM_NOTIFICATION_SOUND => 0;
use constant DEFAULT_CUSTOMIZE_USE_HOOK_DESCRIPTION => 0;



# Declare options.

my $help;

my $config_file;
my $config_file_present;
my $check_config;

my $port;
my $address;

my $auth_enabled;
my $auth_timeout;

my $use_mqtt;
my $mqtt_server; 
my $mqtt_username;
my $mqtt_password;

my $use_fcm;
my $fcm_api_key;
my $token_file;

my $ssl_enabled;
my $ssl_cert_file;
my $ssl_key_file;

my $verbose;
my $event_check_interval;
my $monitor_reload_interval;
my $read_alarm_cause;
my $tag_alarm_event_id;
my $use_custom_notification_sound;

my $hook;
my $use_hook_description;

#default key. Please don't change this
use constant NINJA_API_KEY => "AAAApYcZ0mA:APA91bG71SfBuYIaWHJorjmBQB3cAN7OMT7bAxKuV3ByJ4JiIGumG6cQw0Bo6_fHGaWoo4Bl-SlCdxbivTv5Z-2XPf0m86wsebNIG15pyUHojzmRvJKySNwfAHs7sprTGsA_SIR_H43h";

my $dummyEventTest = 0; # if on, will generate dummy events. Not in config for a reason. Only dev testing
my $dummyEventInterval = 20; # timespan to generate events in seconds
my $dummyEventTimeLastSent = time();


# This part makes sure we have the right core deps. See later for optional deps

if (!try_use ("Net::WebSocket::Server")) {Fatal ("Net::WebSocket::Server missing");}
if (!try_use ("IO::Socket::SSL")) {Fatal ("IO::Socket::SSL missing");}
if (!try_use ("Config::IniFiles")) {Fatal ("Config::Inifiles missing");}
if (!try_use ("Getopt::Long")) {Fatal ("Getopt::Long missing");}
if (!try_use ("File::Basename")) {Fatal ("File::Basename missing");}
if (!try_use ("File::Spec")) {Fatal ("File::Spec missing");}
if (!try_use ("Crypt::MySQL qw(password password41)")) {Fatal ("Crypt::MySQL  missing");}

#if (!try_use ("threads")) {Fatal ("threads library/support  missing");}


use constant USAGE => <<'USAGE';

Usage: zmeventnotification.pl [OPTION]...

  --help                              Print this page.

  --config=FILE                       Read options from configuration file (default: /etc/zmeventnotification.ini).
                                      Any CLI options used below will override config settings.

  --check-config                      Print configuration and exit.

  --port=PORT                         Port for Websockets connection (default: 9000).
  --address=ADDRESS                   Address for Websockets server (default: [::]).

  --enable-auth                       Check username/password against ZoneMinder database (default: true).
  --no-enable-auth                    Don't check username/password against ZoneMinder database (default: false).

  --enable-fcm                        Use FCM for messaging (default: true).
  --no-enable-fcm                     Don't use FCM for messaging (default: false).
  --enable-mqtt                       Use MQTT for messaging (default: false).
  --mqtt-server=SERVER                MQTT messaging server (default: 127.0.0.1). 
  --mqtt-username=USERNAME            MQTT username (default: unset)
  --mqtt-password=PASSWORD            MQTT password (default: unset)   
  --no-enable-mqtt                    Disable MQTT for messaging (default: true).
  --fcm-api-key=KEY                   API key for FCM (default: zmNinja FCM key).
  --token-file=FILE                   Auth token store location (default: /etc/private/tokens.txt).

  --enable-ssl                        Enable SSL (default: true).
  --no-enable-ssl                     Disable SSL (default: false).
  --ssl-cert-file=FILE                Location to SSL cert file.
  --ssl-key-file=FILE                 Location to SSL key file.

  --verbose                           Display messages to console (default: false).
  --no-verbose                        Don't display messages to console (default: true).
  --event-check-interval=SECONDS      Interval, in seconds, after which we will check for new events (default: 5).
  --monitor-reload-interval=SECONDS   Interval, in seconds, to reload known monitors (default: 300).
  --read-alarm-cause                  Read monitor alarm cause (Requires ZoneMinder >= 1.31.2, default: false).
  --no-read-alarm-cause               Don't read monitor alarm cause (default: true).
  --tag-alarm-event-id                Tag event IDs with the alarm (default: false).
  --no-tag-alarm-event-id             Don't tag event IDs with the alarm (default: true).
  --use-custom-notification-sound     Use custom notification sound (default: true).
  --no-use-custom-notification-sound  Don't use custom notification sound (default: false).

  --hook=FILE                         Intercept events before they are reported to do custom processing.
  --use-hook-description              Overwrite alarm text with content returned by hook script (default: true).
  --no-use-hook-description           Do not overwrite alarm text with content returned by hook script (default: false).

USAGE

GetOptions(
  "help"                           => \$help,

  "config=s"                       => \$config_file,
  "check-config"                   => \$check_config,

  "port=i"                         => \$port,
  "address=s"                      => \$address,

  "enable-auth!"                   => \$auth_enabled,
  
  "enable-mqtt!"                    => \$use_mqtt,
  "mqtt-server=s"                  => \$mqtt_server,
  "mqtt-username=s"                  => \$mqtt_username,
  "mqtt-password=s"                  => \$mqtt_password,

  "enable-fcm!"                    => \$use_fcm,
  "fcm-api-key=s"                  => \$fcm_api_key,
  "token-file=s"                   => \$token_file,

  "enable-ssl!"                    => \$ssl_enabled,
  "ssl-cert-file=s"                => \$ssl_cert_file,
  "ssl-key-file=s"                 => \$ssl_key_file,

  "verbose!"                       => \$verbose,
  "event-check-interval=i"         => \$event_check_interval,
  "monitor-reload-interval=i"      => \$monitor_reload_interval,
  "read-alarm-cause!"              => \$read_alarm_cause,
  "tag-alarm-event-id!"            => \$tag_alarm_event_id,
  "use-custom-notification-sound!" => \$use_custom_notification_sound,

  "hook=s"                         => \$hook,
  "use-hook-description!"          => \$use_hook_description
);

exit(print(USAGE)) if $help;

# Read options from a configuration file.  If --config is specified, try to
# read it and fail if it can't be read.  Otherwise, try the default
# configuration path, and if it doesn't exist, take all the default values by
# loading a blank Config::IniFiles object.

if (! $config_file) {
  $config_file = DEFAULT_CONFIG_FILE;
  $config_file_present = -e $config_file;
} else {
  if ( ! -e $config_file) {
    Fatal ("$config_file does not exist!"); 
  }
  $config_file_present = 1;
}

my $config;

if ($config_file_present) {
  Info ("using config file: $config_file");
  $config = Config::IniFiles->new(-file => $config_file);

  unless ($config) {
    Fatal(
      "Encountered errors while reading $config_file:\n" .
      join("\n", @Config::IniFiles::errors)
    );
  }
} else {
  $config = Config::IniFiles->new;
  Info ("No config file found, using inbuilt defaults");
}

# If an option set a value, leave it.  If there's a value in the config, use
# it.  Otherwise, use a default value if it's available.


$port //= config_get_val($config, "network", "port", DEFAULT_PORT);
$address //= config_get_val($config, "network", "address", DEFAULT_ADDRESS);

$auth_enabled //= config_get_val($config, "auth", "enable",  DEFAULT_AUTH_ENABLE);
$auth_timeout //= config_get_val($config, "auth", "timeout", DEFAULT_AUTH_TIMEOUT);

$use_mqtt    //= config_get_val($config, "mqtt", "enable",     DEFAULT_MQTT_ENABLE);
$mqtt_server  //= config_get_val($config, "mqtt", "server",    DEFAULT_MQTT_SERVER);
$mqtt_username //= config_get_val($config, "mqtt", "username");
$mqtt_password //= config_get_val($config, "mqtt", "password");

$use_fcm     //= config_get_val($config, "fcm", "enable",     DEFAULT_FCM_ENABLE);
$fcm_api_key //= config_get_val($config, "fcm", "api_key", NINJA_API_KEY);
$token_file  //= config_get_val($config, "fcm", "token_file", DEFAULT_FCM_TOKEN_FILE);

$ssl_enabled   //= config_get_val($config, "ssl", "enable", DEFAULT_SSL_ENABLE);
$ssl_cert_file //= config_get_val($config, "ssl", "cert");
$ssl_key_file  //= config_get_val($config, "ssl", "key");

$verbose                       //= config_get_val($config, "customize", "verbose", DEFAULT_CUSTOMIZE_VERBOSE);
$event_check_interval          //= config_get_val($config, "customize", "event_check_interval", DEFAULT_CUSTOMIZE_EVENT_CHECK_INTERVAL);
$monitor_reload_interval       //= config_get_val($config, "customize", "monitor_reload_interval", DEFAULT_CUSTOMIZE_MONITOR_RELOAD_INTERVAL);
$read_alarm_cause              //= config_get_val($config, "customize", "read_alarm_cause", DEFAULT_CUSTOMIZE_READ_ALARM_CAUSE);
$tag_alarm_event_id            //= config_get_val($config, "customize", "tag_alarm_event_id", DEFAULT_CUSTOMIZE_TAG_ALARM_EVENT_ID);
$use_custom_notification_sound //= config_get_val($config, "customize", "use_custom_notification_sound",DEFAULT_CUSTOMIZE_USE_CUSTOM_NOTIFICATION_SOUND);

$hook                         //= config_get_val($config, "customize", "hook");
$use_hook_description         //= config_get_val($config, "customize", "use_hook_description", DEFAULT_CUSTOMIZE_USE_HOOK_DESCRIPTION);

my %ssl_push_opts = ();

if ($ssl_enabled && (!$ssl_cert_file || !$ssl_key_file)) {
    Fatal ("SSL is enabled, but key or certificate file is missing");
}

my $notId = 1;

use constant PENDING_WEBSOCKET => '1';
use constant INVALID_WEBSOCKET => '-1';
use constant INVALID_APNS      => '-2';
use constant INVALID_AUTH      => '-3';
use constant INVALID_REMOTE    => '-4';
use constant VALID_WEBSOCKET   => '0';

# this is just a wrapper around Config::IniFiles val
# older versions don't support a default parameter
sub config_get_val {
    my ( $config, $sect, $parm, $def ) = @_;
    my $val = $config->val($sect, $parm);
    return defined($val)? $val:$def;
}

# helper routines to print config status in help
sub true_or_false {
  return $_[0] ? "true" : "false";
}

sub value_or_undefined {
  return $_[0] || "(undefined)";
}


sub present_or_not {
  return $_[0] ? "(defined)" : "(undefined)";
}

sub print_config {
  my $abs_config_file = File::Spec->rel2abs($config_file);

  print(<<"EOF"

${\(
  $config_file_present ?
  "Configuration (read $abs_config_file)" :
  "Default configuration ($abs_config_file doesn't exist)"
)}:

Port .......................... ${\(value_or_undefined($port))}
Address ....................... ${\(value_or_undefined($address))}
Event check interval .......... ${\(value_or_undefined($event_check_interval))}
Monitor reload interval ....... ${\(value_or_undefined($monitor_reload_interval))}

Auth enabled .................. ${\(true_or_false($auth_enabled))}
Auth timeout .................. ${\(value_or_undefined($auth_timeout))}

Use FCM ....................... ${\(true_or_false($use_fcm))}
FCM API key ................... ${\(present_or_not($fcm_api_key))}
Token file .................... ${\(value_or_undefined($token_file))}

Use MQTT .......................${\(true_or_false($use_mqtt))}
MQTT Server ....................${\(value_or_undefined($mqtt_server))}
MQTT Username ..................${\(value_or_undefined($mqtt_username))}
MQTT Password ..................${\(present_or_not($mqtt_password))}

SSL enabled ................... ${\(true_or_false($ssl_enabled))}
SSL cert file ................. ${\(value_or_undefined($ssl_cert_file))}
SSL key file .................. ${\(value_or_undefined($ssl_key_file))}

Verbose ....................... ${\(true_or_false($verbose))}
Read alarm cause .............. ${\(true_or_false($read_alarm_cause))}
Tag alarm event id ............ ${\(true_or_false($tag_alarm_event_id))}
Use custom notification sound . ${\(true_or_false($use_custom_notification_sound))}

Hook .......................... ${\(value_or_undefined($hook))}
Use Hook Description........... ${\(true_or_false($use_hook_description))}

EOF
  )
}

exit(print_config()) if $check_config;
print_config() if $verbose;

 
# Lets now load all the optional dependent libraries in a failsafe way

if (!try_use ("JSON")) 
{ 
    if (!try_use ("JSON::XS")) 
    { Fatal ("JSON or JSON::XS  missing");exit (-1);}
}
# Fetch whatever options are available from CLI arguments.

if ($use_fcm)
{
    if (!try_use ("LWP::UserAgent") || !try_use ("URI::URL") || !try_use("LWP::Protocol::https"))
    {
        Fatal ("FCM push mode needs LWP::Protocol::https, LWP::UserAgent and URI::URL perl packages installed");
    }
    else
    {
        Info ("Push enabled via FCM");
    }
    
}
else
{
    Info ("FCM disabled. Will only send out websocket notifications");
}

if ($use_mqtt)
{
    if (!try_use ("Net::MQTT::Simple")) {Fatal ("Net::MQTT::Simple  missing");exit (-1);}
    if (defined $mqtt_username)
    {
        if (!try_use ("Net::MQTT::Simple::Auth")) {Fatal ("Net::MQTT::Simple::Auth  missing");exit (-1);}
    }
    Info ("Broadcasting Events to MQTT");

}
else 
{
    Info ("MQTT Disabled");
}

# ==========================================================================
#
# Don't change anything below here
#
# ==========================================================================

use lib '/usr/local/lib/x86_64-linux-gnu/perl5';
use ZoneMinder;
use POSIX;
use DBI;

#$SIG{CHLD}='IGNORE';
$| = 1;

$ENV{PATH}  = '/bin:/usr/bin';
$ENV{SHELL} = '/bin/sh' if exists $ENV{SHELL};
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

sub Usage
{
        print( "This daemon is not meant to be invoked from command line\n");
    exit( -1 );
}

logInit();
logSetSignal();


my $dbh = zmDbConnect();
my %monitors;
my $monitor_reload_time = 0;
my $apns_feedback_time = 0;
my $proxy_reach_time=0;
my $wss;
my @events=();
my @active_connections=();
my $alarm_monitor_name="";
my $alarm_header="";
my $alarm_mid="";
my $alarm_eid="";
my $needsReload = 0;

# Main entry point

printdbg ("******You are running version: $app_version");
printdbg ("WARNING: SSL is disabled, which means all traffic will be unencrypted!") unless $ssl_enabled;

if ($use_fcm)
{
    my $dir = dirname($token_file);
    if ( ! -d $dir)
    {

        Info ("Creating $dir to store FCM tokens");
        mkdir $dir;
    }
}




Info( "Event Notification daemon v $app_version starting\n" );
loadTokens();
initSocketServer();
Info( "Event Notification daemon exiting\n" );
exit();

# Try to load a perl module
# and if it is not available 
# generate a log 

sub try_use 
{
  my $module = shift;
  eval("use $module");
  return($@ ? 0:1);
}

# console print
sub printdbg 
{
	my $a = shift;
    my $now = strftime('%Y-%m-%d,%H:%M:%S',localtime);
    print($now," ",$a, "\n") if $verbose;
}

# This function uses shared memory polling to check if 
# ZM reported any new events. If it does find events
# then the details are packaged into the events array
# so they can be JSONified and sent out
sub checkEvents()
{
    
    my $eventFound = 0;
    if ( $needsReload || ((time() - $monitor_reload_time) > $monitor_reload_interval ))
    {
        my $len = scalar @active_connections;
        Info ("Total event client connections: ".$len."\n");
        my $ndx = 1;
        foreach (@active_connections)
        {
            
          my $cip="(none)";
          if (exists $_->{conn} )
          {
              $cip = $_->{conn}->ip();
          }
          Debug ("-->Connection $ndx: IP->".$cip." Token->:".$_->{token}." Plat:".$_->{platform}." Push:".$_->{pushstate}); 
          printdbg ("-->Connection $ndx: IP->".$cip." Token->".$_->{token}." Plat:".$_->{platform}." Push:".$_->{pushstate});
          $ndx++;
        }
        Info ("Reloading Monitors...\n");
        foreach my $monitor (values(%monitors))
        {
            zmMemInvalidate( $monitor );
        }
        loadMonitors();
        $needsReload = 0;
    }
    @events = ();
    $alarm_header = "";
    $alarm_mid="";
    $alarm_eid = ""; # only take 1 if several occur
    foreach my $monitor ( values(%monitors) )
    { 
         my $alarm_cause="";

         if (  !zmMemVerify($monitor) ) {
          # Our attempt to verify the memory handle failed. We should reload the monitors.
          # Don't need to zmMemInvalidate because the monitor reload will do it.
          $needsReload = 1;
          Error ("** Memory verify failed for ".$monitor->{Name}."(id:".$monitor->{Id}. ") so forcing reload");
          next;
          }
         my ( $state, $last_event, $trigger_cause, $trigger_text)
            = zmMemRead( $monitor,
                 [ "shared_data:state",
                   "shared_data:last_event",
                   "trigger_data:trigger_cause",
                   "trigger_data:trigger_text",
                 ]
            );

        if ($state == STATE_ALARM || $state == STATE_ALERT)
        {
            Debug ("state is STATE_ALARM or ALERT for ".$monitor->{Name});
            if ( !defined($monitor->{LastEvent})
                         || ($last_event != $monitor->{LastEvent}))
            {
                $alarm_cause=zmMemRead($monitor,"shared_data:alarm_cause") if ($read_alarm_cause);
                $alarm_cause = $trigger_cause if (defined($trigger_cause) && $alarm_cause eq "" && $trigger_cause ne "");
                printdbg ("Unified Alarm details: $alarm_cause");
                Info( "New event $last_event reported for ".$monitor->{Name}." ".$alarm_cause."\n");
                $monitor->{LastState} = $state;
                $monitor->{LastEvent} = $last_event;
                my $name = $monitor->{Name};
                my $mid = $monitor->{Id};
                my $eid = $last_event;
                Debug ("Creating event object for ".$monitor->{Name}." with $last_event");
                push @events, {Name => $name, MonitorId => $mid, EventId => $last_event, Cause=> $alarm_cause};
                $alarm_eid = $last_event;
                $alarm_header = "Alarms: " if (!$alarm_header);
                $alarm_header = $alarm_header . $name ;
                $alarm_header = $alarm_header." ".$alarm_cause if (defined $alarm_cause);
                $alarm_header = $alarm_header." ".$trigger_cause if (defined $trigger_cause);
                $alarm_mid = $alarm_mid.$mid.",";
                $alarm_header = $alarm_header . " (".$last_event.") " if ($tag_alarm_event_id);
                $alarm_header = $alarm_header . "," ;
                $alarm_monitor_name = $monitor->{Name};
                $eventFound = 1;
            }
            
        }
    }
    chop($alarm_header) if ($alarm_header);
    chop ($alarm_mid) if ($alarm_mid);

    # Send out dummy events for testing
    if (!$eventFound && $dummyEventTest && (time() - $dummyEventTimeLastSent) >= $dummyEventInterval ) {
        $dummyEventTimeLastSent = time();
        my $random_mon = $monitors{(keys %monitors)[rand keys %monitors]};
        Info ("Sending dummy event to: ".$random_mon->{Name});
        push @events, {Name => $random_mon->{Name}, MonitorId => $random_mon->{Id}, EventId => $random_mon->{LastEvent}, Cause=> "Dummy"};
        $alarm_header = "Alarms: Dummy alarm at ".$random_mon->{Name};
        $alarm_mid = $random_mon->{Id};
        $eventFound = 1;

    }

    return ($eventFound);
}

# Refreshes list of monitors from DB
# 
sub loadMonitors
{
      Info( "Loading monitors\n" );
      $monitor_reload_time = time();

      my %new_monitors = ();

      my $sql = "SELECT * FROM Monitors
        WHERE find_in_set( Function, 'Modect,Mocord,Nodect' )".
        ( $Config{ZM_SERVER_ID} ? 'AND ServerId=?' : '' )
        ;
      my $sth = $dbh->prepare_cached( $sql )
        or Fatal( "Can't prepare '$sql': ".$dbh->errstr() );
      my $res = $sth->execute( $Config{ZM_SERVER_ID} ? $Config{ZM_SERVER_ID} : () )
        or Fatal( "Can't execute: ".$sth->errstr() );
      while( my $monitor = $sth->fetchrow_hashref() ) {
        if ( zmMemVerify( $monitor ) ) {
            $monitor->{LastState} = zmGetMonitorState( $monitor );
            $monitor->{LastEvent} = zmGetLastEvent( $monitor );
        }
        $new_monitors{$monitor->{Id}} = $monitor;
      } # end while fetchrow
      %monitors = %new_monitors;
}



# This function compares the password provided over websockets
# to the password stored in the ZM MYSQL DB

sub validateZM
{
    return 1 unless $auth_enabled;
    my ($u,$p) = @_;
    return 0 if ( $u eq "" || $p eq "");
    my $sql = 'select Password from Users where Username=?';
    my $sth = $dbh->prepare_cached($sql)
     or Fatal( "Can't prepare '$sql': ".$dbh->errstr() );
        my $res = $sth->execute( $u )
    or Fatal( "Can't execute: ".$sth->errstr() );
    if (my ($state) = $sth->fetchrow_hashref())
    {
        my $encryptedPassword = password41($p);
        $sth->finish();
        return $state->{Password} eq $encryptedPassword ? 1:0; 
    }
    else
    {
        $sth->finish();
        return 0;
    }

}

# deletes a token - invoked if FCM responds with an incorrect token error
sub deleteToken
{
    my $dtoken = shift;
    printdbg ("DeleteToken called with $dtoken");
    return if ( ! -f $token_file);
    
    open (my $fh, '<', $token_file);
    chomp( my @lines = <$fh>);
    close ($fh);
    my @uniquetokens = uniq(@lines);

    open ($fh, '>', $token_file);

    foreach(@uniquetokens)
    {
        my ($token, $monlist, $intlist, $platform, $pushstate)  = rsplit(qr/:/, $_, 5); #split (":",$_);
        next if ($_ eq "" || $token eq $dtoken);
        print $fh "$_\n";
        #print "delete: $row\n";
        push @active_connections, {
                       token => $token,
                       pending => VALID_WEBSOCKET,
                       time=>time(),
                       badge => 0,
                       monlist => $monlist,
                       intlist => $intlist,
                       last_sent=>{},
                       platform => $platform,
                       pushstate => $pushstate
                      };
        
    }
    close ($fh);
}


# Sends a push notification to the mqtt Broker
sub sendOverMQTTBroker
{

    my ($header, $mid) = @_;
    my $json;
    my $mqtt;

    $json = encode_json ({
                monitor=> $mid,
                name=>$header,
                state => 'alarm',
            });

    Debug ("Final JSON being sent is: $json");

    if (defined $mqtt_username && defined $mqtt_password)
    {
        $mqtt = Net::MQTT::Simple::Auth->new($mqtt_server, $mqtt_username, $mqtt_password);
    }
    else 
    {
        $mqtt = Net::MQTT::Simple->new($mqtt_server);
    }

    $mqtt->publish(join('/','zoneminder',$mid) => $json);
}




# Sends a push notification to FCM
sub sendOverFCM
{
    
    my ($obj, $header, $mid, $eid,  $str, $mname) = @_;
    
    my $now = strftime('%I:%M %p, %b-%d',localtime);
    $obj->{badge}++;
    my $uri = "https://fcm.googleapis.com/fcm/send";
    my $json;
    # use zmNinja FCM key if the user did not override
    my $key="key=" . $fcm_api_key;

    
    if ($obj->{platform} eq "ios")
    {
        $json = encode_json ({
            
            to=>$obj->{token},
            notification=> {
               title=>$mname." Alarm",
               body=>$header." at ".$now,
               sound=>"default",
               badge=>$obj->{badge},
            },
           data=> {
               myMessageId=> $notId,
               mid=>$mid,
               eid=>$eid,
          },
        });
    }
    # if I do both, notification icon in Android gets messed up
    else  { # android 
        $json = encode_json ({
            to=>$obj->{token},
            data=> {
                title=>$mname." Alarm",
                message=>$header." at ".$now,
                #"force-start"=>1,
                style=>"inbox",
                myMessageId=> $notId,
                #summaryText=>"Summary",
                #body=>"My text",
                icon=>"ic_stat_notification",
              #  "content-available"=> "1",
                mid=>$mid,
                eid=>$eid,
            }
        });
        $notId = ($notId +1) % 100000;
        
    }

    #print "Sending:$json\n";
    Debug ("Final JSON being sent is: $json");
    my $req = HTTP::Request->new ('POST', $uri);
    $req->header( 'Content-Type' => 'application/json', 'Authorization'=> $key);
     $req->content($json);
    my $lwp = LWP::UserAgent->new(%ssl_push_opts);
    my $res = $lwp->request( $req );
	my $msg;
	my $json_string;
    if ($res->is_success)
    {
        $msg = $res->decoded_content;
        Info ("FCM push message returned a 200 with body ".$res->content);
        eval {$json_string = decode_json($msg);};
        if ($@)
        {
            
            Error ("Failed decoding sendFCM Response: $@");
            return;
        }
        if ($json_string->{'failure'} eq 1) {
            my $reason =  $json_string->{'results'}[0]->{'error'};
            Error ("Error sending FCM for token:".$obj->{token});
            Error ("Error value =".$reason);
            if ($reason eq "NotRegistered" || $reason eq "InvalidRegistration") {
                Info ("Removing this token as FCM doesn't recognize it");
                deleteToken($obj->{token});
            }

        }
    }
    else
    {
        Info("FCM push message Error:".$res->status_line);
    }

}


# This runs at each tick to purge connections
# that are inactive or have had an error
# This also closes any connection that has not provided
# credentials in the time configured after opening a socket
sub checkConnection
{
    foreach (@active_connections)
    {
        my $curtime = time();
        if ($_->{pending} == PENDING_WEBSOCKET)
        {
            # This takes care of purging connections that have not authenticated
            if ($curtime - $_->{time} > $auth_timeout)
            {
            # What happens if auth is not provided but device token is registered?
            # It may still be a bogus token, so don't risk keeping connection stored
                if (exists $_->{conn})
                {
                    my $conn = $_->{conn};
                    Info ("Rejecting ".$conn->ip()." - authentication timeout");
                    printdbg ("Rejecting ".$conn->ip()." - authentication timeout marking as INVALID_AUTH");
                    $_->{pending} = INVALID_AUTH;
                    my $str = encode_json({event => 'auth', type=>'',status=>'Fail', reason => 'NOAUTH'});
                    eval {$_->{conn}->send_utf8($str);};
                    $_->{conn}->disconnect();
                }
            }
        }

    }
    my $ac1 = scalar @active_connections;
    @active_connections = grep { $_->{pending} != INVALID_AUTH   } @active_connections;
    $ac1 = scalar @active_connections;
    #printdbg ("Active connects after INVALID_AUTH purge=$ac1");
    @active_connections = grep { $_->{pending} != INVALID_REMOTE   } @active_connections;
    $ac1 = scalar @active_connections;

#    commented out - seems like if the app exists and websocket is closed, this code
#    eventually results in the token being removed from tokens.txt which I don't want
#    my $purged = $ac1 - scalar @active_connections;
#    if ($purged > 0)
#    {
#        $ac1 = $ac1 - $purged;
#        Debug ("Active connects after INVALID_AUTH purge=$ac1 ($purged purged)");
#    }
#
#    @active_connections = grep { $_->{pending} != INVALID_WEBSOCKET   } @active_connections;
#    my $purged = $ac1 - scalar @active_connections;
#    if ($purged > 0)
#    {
#        $ac1 = $ac1 - $purged;
#        Debug ("Active connects after INVALID_WEBSOCKET purge=$ac1 ($purged purged)");
#    }

    if ($use_fcm)
    {
        #@active_connections = grep { $_->{'pending'} != INVALID_APNS || $_->{'token'} ne ''} @active_connections;
        @active_connections = grep { $_->{'pending'} != INVALID_APNS} @active_connections;
        $ac1 = scalar @active_connections;
        #printdbg ("Active connects after INVALID_APNS purge=$ac1");
    }
}

# tokens can have : , so right split - this way I don't break existing token files
# http://stackoverflow.com/a/37870235/1361529
sub rsplit {
    my $pattern = shift(@_);    # Precompiled regex pattern (i.e. qr/pattern/)
    my $expr    = shift(@_);    # String to split
    my $limit   = shift(@_);    # Number of chunks to split into
    map { scalar reverse($_) } reverse split(/$pattern/, scalar reverse($expr), $limit);
}

# This function  is called whenever we receive a message from a client

sub checkMessage
{
    my ($conn, $msg) = @_;  
    
    my $json_string;
    eval {$json_string = decode_json($msg);};
    if ($@)
    {
        
        Info ("Failed decoding json in checkMessage: $@");
        my $str = encode_json({event=> 'malformed', type=>'', status=>'Fail', reason=>'BADJSON'});
        eval {$conn->send_utf8($str);};
        return;
    }

    # This event type is when a command related to push notification is received
    if (($json_string->{'event'} eq "push") && !$use_fcm)
    {
        my $str = encode_json({event=>'push', type=>'',status=>'Fail', reason => 'PUSHDISABLED'});
        eval {$conn->send_utf8($str);};
        return;
    }
    #-----------------------------------------------------------------------------------
    # "push" event processing
    #-----------------------------------------------------------------------------------
    elsif (($json_string->{'event'} eq "push") && $use_fcm)
    {
        # sets the unread event count of events for a specific connection
        # the server keeps a tab of # of events it pushes out per connection
        # but won't know when the client has read them, so the client call tell the server
        # using this message
        if ($json_string->{'data'}->{'type'} eq "badge")
        {
            foreach (@active_connections)
            {
                if ((exists $_->{conn}) && ($_->{conn}->ip() eq $conn->ip())  &&
                    ($_->{conn}->port() eq $conn->port()))  
                {

                    #print "Badge match, setting to 0\n";
                    $_->{badge} = $json_string->{'data'}->{'badge'};
                }
            }
            return;
        }
        # This sub type is when a device token is registered
        if ($json_string->{'data'}->{'type'} eq "token")
        {
            
            # a token must have a platform 
            if (!$json_string->{'data'}->{'platform'})
            {
                my $str = encode_json({event=>'push', type=>'token',status=>'Fail', reason => 'MISSINGPLATFORM'});
                eval {$conn->send_utf8($str);};
                return;
            }
            foreach (@active_connections)
            {
                # this token already exists
                if ($_->{token} eq $json_string->{'data'}->{'token'}) 
                {
                    # if the token doesn't belong to the same connection
                    # then we have two connections owning the same token
                    # so we need to delete the old one. This can happen when you load
                    # the token from the persistent file and there is no connection
                    # and then the client is loaded 
                    if ( (!exists $_->{conn}) || ($_->{conn}->ip() ne $conn->ip() 
                        && $_->{conn}->port() ne $conn->port()))
                    {
                        printdbg ("REGISTRATION: marking ".$_->{token}." as INVALID_APNS");
                        
                        $_->{pending} = INVALID_APNS;
                        Info ("Duplicate token found, removing old data point");


                    }
                    else # token matches and connection matches, so it may be an update
                    {
                        $_->{token} = $json_string->{'data'}->{'token'};
                        $_->{platform} = $json_string->{'data'}->{'platform'};
                        if (exists($json_string->{'data'}->{'monlist'}) && ($json_string->{'data'}->{'monlist'} ne ""))
                        {
                            $_->{monlist} = $json_string->{'data'}->{'monlist'};
                        }
                        else
                        {
                            $_->{monlist} = "-1";
                        }
                        if (exists($json_string->{'data'}->{'intlist'}) && ($json_string->{'data'}->{'intlist'} ne ""))
                        {
                            $_->{intlist} = $json_string->{'data'}->{'intlist'};
                        }
                        else
                        {
                             $_->{intlist} = "-1";
                        }
                        $_->{pushstate} = $json_string->{'data'}->{'state'};
                        Info ("Storing token ...".substr($_->{token},-10).",monlist:".$_->{monlist}.",intlist:".$_->{intlist}.",pushstate:".$_->{pushstate}."\n");
                        my ($emonlist,$eintlist) = saveTokens($_->{token}, $_->{monlist}, $_->{intlist}, $_->{platform}, $_->{pushstate});
                        $_->{monlist} = $emonlist;
                        $_->{intlist} = $eintlist;
                    } # token and conn. matches
                } # end of token matches

                # The connection matches but the token does not 
                # this can happen if this is the first token registration after push notification registration
                # response is received
                elsif ( (exists $_->{conn}) && ($_->{conn}->ip() eq $conn->ip())  &&
                    ($_->{conn}->port() eq $conn->port()))  
                {
                    $_->{token} = $json_string->{'data'}->{'token'};
                    $_->{platform} = $json_string->{'data'}->{'platform'};
                    $_->{monlist} = $json_string->{'data'}->{'monlist'};
                    $_->{intlist} = $json_string->{'data'}->{'intlist'};
                    if (exists($json_string->{'data'}->{'monlist'}) && ($json_string->{'data'}->{'monlist'} ne ""))
                    {
                        $_->{monlist} = $json_string->{'data'}->{'monlist'};
                    }
                    else
                    {
                            $_->{monlist} = "-1";
                    }
                    if (exists($json_string->{'data'}->{'intlist'}) && ($json_string->{'data'}->{'intlist'} ne ""))
                    {
                        $_->{intlist} = $json_string->{'data'}->{'intlist'};
                    }
                    else
                    {
                            $_->{intlist} = "-1";
                    }
                            $_->{pushstate} = $json_string->{'data'}->{'state'};
                            Info ("Storing token ...".substr($_->{token},-10).",monlist:".$_->{monlist}.",intlist:".$_->{intlist}.",pushstate:".$_->{pushstate}."\n");
                            my ($emonlist,$eintlist) = saveTokens($_->{token}, $_->{monlist}, $_->{intlist}, $_->{platform}, $_->{pushstate});
                            $_->{monlist} = $emonlist;
                            $_->{intlist} = $eintlist;


                }
            }

                
        }
        
    } # event = push
    #-----------------------------------------------------------------------------------
    # "control" event processing
    #-----------------------------------------------------------------------------------
    elsif (($json_string->{'event'} eq "control") )
    {
        if  ($json_string->{'data'}->{'type'} eq "filter")
        {
            if (!exists($json_string->{'data'}->{'monlist'}))
            {
                my $str = encode_json({event=>'control', type=>'filter',status=>'Fail', reason => 'MISSINGMONITORLIST'});
                eval {$conn->send_utf8($str);};
                return;
            }
            if ( !exists($json_string->{'data'}->{'intlist'}))
            {
                my $str = encode_json({event=>'control', type=>'filter',status=>'Fail', reason => 'MISSINGINTERVALLIST'});
                eval {$conn->send_utf8($str);};
                return;
            }
            my $monlist = $json_string->{'data'}->{'monlist'};
            my $intlist = $json_string->{'data'}->{'intlist'};
            #print ("CONTROL GOT: $monlist and $intlist\n");
            foreach (@active_connections)
            {
                if ((exists $_->{conn}) && ($_->{conn}->ip() eq $conn->ip())  &&
                    ($_->{conn}->port() eq $conn->port()))  
                {

                    $_->{monlist} = $monlist;
                    $_->{intlist} = $intlist;
                    Info ("Contrl: Storing token ...".substr($_->{token},-10).",monlist:".$_->{monlist}.",intlist:".$_->{intlist}.",pushstate:".$_->{pushstate}."\n");
                    saveTokens($_->{token}, $_->{monlist}, $_->{intlist}, $_->{platform}, $_->{pushstate}); 
                }
            }
        }   
        if  ($json_string->{'data'}->{'type'} eq "version")
        {
            foreach (@active_connections)
            {
                if ((exists $_->{conn}) && ($_->{conn}->ip() eq $conn->ip())  &&
                    ($_->{conn}->port() eq $conn->port()))  
                {
                    my $str = encode_json({event=>'control',type=>'version', status=>'Success', reason => '', version => $app_version});
                    eval {$_->{conn}->send_utf8($str);};

                }
            }
        }

    } # event = control


    #-----------------------------------------------------------------------------------
    # "auth" event processing
    #-----------------------------------------------------------------------------------
    # This event type is when a command related to authorization is sent
    elsif ($json_string->{'event'} eq "auth")
    {
        my $uname = $json_string->{'data'}->{'user'};
        my $pwd = $json_string->{'data'}->{'password'};
    
        foreach (@active_connections)
        {
            if ( (exists $_->{conn}) &&
                ($_->{conn}->ip() eq $conn->ip())  &&
                ($_->{conn}->port() eq $conn->port())  &&
                ($_->{pending}==PENDING_WEBSOCKET))
            {
                if (!validateZM($uname,$pwd))
                {
                    # bad username or password, so reject and mark for deletion
                    my $str = encode_json({event=>'auth', type=>'', status=>'Fail', reason => 'BADAUTH'});
                    eval {$_->{conn}->send_utf8($str);};
                    Info("Bad authentication provided by ".$_->{conn}->ip());
                    printdbg("marking INVALID_AUTH Bad authentication provided by ".$_->{conn}->ip());
                    $_->{pending}=INVALID_AUTH;
                }
                else
                {


                    # all good, connection auth was valid
                    $_->{pending}=VALID_WEBSOCKET;
                    $_->{token}='';
                    my $str = encode_json({event=>'auth', type=>'', status=>'Success', reason => '', version => $app_version});
                    eval {$_->{conn}->send_utf8($str);};
                    Info("Correct authentication provided by ".$_->{conn}->ip());
                    
                }
            }
        }
    } # event = auth
    else
    {
                    my $str = encode_json({event=>$json_string->{'event'},type=>'', status=>'Fail', reason => 'NOTSUPPORTED'});
                    eval {$_->{conn}->send_utf8($str);};
    }
}

# This loads APNS tokens stored in a conf file
# This ensures even if the daemon dies and 
# restarts APNS tokens are maintained
# I also maintain monitor filter list
# so that APNS notifications will only be pushed
# for the monitors that are configured against
# that token 

sub loadTokens
{
    return if (!$use_fcm);
    if ( ! -f $token_file)
    {
        open (my $foh, '>', $token_file);
        Info ("Creating ".$token_file);
        print $foh "";
        close ($foh);
    }
    
    open (my $fh, '<', $token_file);
    chomp( my @lines = <$fh>);
    close ($fh);



    printdbg ("Calling uniq from loadTokens");
    my @uniquetokens = uniq(@lines);

    open ($fh, '>', $token_file);
    # This makes sure we rewrite the file with
    # unique tokens
    foreach(@uniquetokens)
    {
        next if ($_ eq "");
        print $fh "$_\n";
        my ($token, $monlist, $intlist, $platform, $pushstate)  = rsplit(qr/:/, $_, 5); # split (":",$_);
        push @active_connections, {
               token => $token,
               pending => VALID_WEBSOCKET,
               time=>time(),
               badge => 0,
               monlist => $monlist,
               intlist => $intlist,
               last_sent=>{},
               platform => $platform,
               pushstate => $pushstate
              };
        
    }
    close ($fh);
}

# When a client sends a token id,
# I store it in the file
# It can be sent multiple times, with or without
# monitor list, so I retain the old monitor
# list if its not supplied. In the case of zmNinja
# tokens are sent without monitor list when the registration
# id is received from apple, so we handle that situation

sub saveTokens
{
    return if (!$use_fcm);
    my $stoken = shift;
    if ($stoken eq "") {printdbg ("Not saving, no token. Desktop?"); return};
    my $smonlist = shift;
    my $sintlist = shift;
    my $splatform = shift;
    my $spushstate = shift;
    printdbg ("saveTokens called with=>$stoken:$smonlist:$sintlist:$splatform:$spushstate");
	if (($spushstate eq "") && ($stoken ne "") )
	{
		$spushstate = "enabled";
		Info ("Overriding token state, setting to enabled as I got a null with a valid token");
		printdbg ("Overriding token state, setting to enabled as I got a null with a valid token");
	}

    Info ("SaveTokens called with:monlist=$smonlist, intlist=$sintlist, platform=$splatform, push=$spushstate");
    
    return if ($stoken eq "");
    open (my $fh, '<', $token_file) || Fatal ("Cannot open for read ".$token_file);
    chomp( my @lines = <$fh>);
    close ($fh);
    my @uniquetokens = uniq(@lines);
    my $found = 0;
    open (my $fh, '>', $token_file) || Fatal ("Cannot open for write ".$token_file);
    foreach (@uniquetokens)
    {
        next if ($_ eq "");
        my ($token, $monlist, $intlist, $platform, $pushstate)  = rsplit(qr/:/, $_, 5); #split (":",$_);
        if ($token eq $stoken) # update token in file with new information
        {
	    Info ("token $token matched, previously stored monlist is: $monlist");
            $smonlist = $monlist if ($smonlist eq "-1");
            $sintlist = $intlist if ($sintlist eq "-1");
            $spushstate = $pushstate if ($spushstate eq "");
            printdbg ("updating $token with $pushstate");
            print $fh "$stoken:$smonlist:$sintlist:$splatform:$spushstate\n";
	        Info ("overwriting $token monlist with:$smonlist");
            $found = 1;
        }
        else # write token as is
        {
            if ($pushstate eq "") {$pushstate = "enabled"; printdbg ("nochange, but pushstate was EMPTY. WHY?"); }
            printdbg ("no change - saving $token with $pushstate");
            print $fh "$token:$monlist:$intlist:$platform:$pushstate\n";
        }

    }

    $smonlist = "" if ($smonlist eq "-1");
    $sintlist = "" if ($sintlist eq "-1");
    
    if (!$found)
    {
	    Info ("$stoken not found, creating new record with monlist=$smonlist");
        printdbg ("Saving $stoken as it does not exist");
    	print $fh "$stoken:$smonlist:$sintlist:$splatform:$spushstate\n";
    }
    close ($fh);

    return ($smonlist, $sintlist);
    
}

# This keeps the latest of any duplicate tokens
# we need to ignore monitor list when we do this
sub uniq 
{
    my %seen;
    my @array = reverse @_; # we want the latest
    my @farray=();
    foreach (@array)
    {
        next if  ($_ =~ /^\s*$/); # skip blank lines - we don't really need this - as token check is later
        my ($token,$monlist,$intlist,$platform, $pushstate) = rsplit(qr/:/, $_, 5); #split (":",$_);
        next if ($token eq "");
        if (($pushstate ne "enabled") && ($pushstate ne "disabled"))
        {
            printdbg ("huh? uniq read $token,$monlist,$intlist,$platform, $pushstate => forcing state to enabled");
            $pushstate="enabled";
            
        }
        # not interested in monlist & intlist
        if (! $seen{$token}++ )
        {
            push @farray, "$token:$monlist:$intlist:$platform:$pushstate";
            #printdbg ("\@uniq pushing: $token:$monlist:$intlist:$platform:$pushstate");
        }
         
        
    }
    return @farray;
    
    
}
# Checks if the monitor for which
# an alarm occurred is part of the monitor list
# for that connection
sub getInterval
{
    my $intlist = shift;
    my $monlist = shift;
    my $mid = shift;

    #print ("getInterval:MID:$mid INT:$intlist AND MON:$monlist\n");
    my @ints = split (',',$intlist);
    my @mids = split (',',$monlist);
    my $idx = -1;
    foreach (@mids)
    {
        $idx++;
        #print ("Comparing $mid with $_\n");
        if ($mid eq $_)
        {
            last;
        }
    }
    #print ("RETURNING index:$idx with Value:".$ints[$idx]."\n");
    return $ints[$idx];
    
}
# Checks if the monitor for which
# an alarm occurred is part of the monitor list
# for that connection
sub isInList
{
    my $monlist = shift;
    my $mid = shift;

    my @mids = split (',',$monlist);
    my $found = 0;
    foreach (@mids)
    {
        if ($mid eq $_)
        {
            $found = 1;
            last;
        }
    }
    return $found;
    
}

sub getIdentity
{
    my $obj=shift;
    my $identity="";
    if (exists $obj->{conn} )
    {
        $identity = $obj->{conn}->ip().":".$obj->{conn}->port();
    }
    if ($obj->{token})
    {
        $identity=$identity." token ending in:...". substr($obj->{token},-10);
    }
    $identity="(unknown)" if (!$identity);
    return $identity;
}
    
sub processAlarms {

    if ($hook) {
        my $cmd = $hook." ".$alarm_eid." ".$alarm_mid." \"".$alarm_monitor_name."\"";
        Info ("Invoking hook:".$cmd);
        my $resTxt = `$cmd`;
        my $resCode = $? >> 8;
        chomp($resTxt);
        Info("hook script returned with text:".$resTxt." exit:".$resCode);
        return if ($resCode !=0);

        $alarm_header = $resTxt if ($use_hook_description);
        
    }

    my $ac = scalar @active_connections;
    if ($use_mqtt) 
    {
        Info ("Sending notification over MQTT");
        sendOverMQTTBroker($alarm_header, $alarm_mid);
    }

    Info ("Broadcasting new events to all $ac websocket clients\n");
    my ($serv) = @_;
    my $i = 0;
    foreach (@active_connections)
    {
        # Let's see if this connection is interested in this alarm
        my $monlist = $_->{monlist};
        my $intlist = $_->{intlist};
        my $last_sent = $_->{last_sent};
        my $obj = $_;
        my $connid = getIdentity($obj);
        Info ("Checking alarm rules for $connid");
        # we need to create a per connection array which will be
        # a subset of main events with the ones that are not in its
        # monlist left out
        my @localevents = ();
        foreach (@events)
        {
            if ($monlist eq "" || isInList($monlist, $_->{MonitorId} ) )
            {
                my $mint = getInterval($intlist, $monlist, $_->{MonitorId});
                my $elapsed;
                if ($last_sent->{$_->{MonitorId}})
                {
                    $elapsed = time() -  $last_sent->{$_->{MonitorId}};
                    if ($elapsed >= $mint)
                    {
                        Info("Monitor ".$_->{MonitorId}." event: sending this out as $elapsed is >= interval of $mint");
                        $_->{Cause} = $alarm_header if ($hook && $use_hook_description);
                        push (@localevents, $_);
                        $last_sent->{$_->{MonitorId}} = time();
                    }
                    else
                    {
                        
                            Info("Monitor ".$_->{MonitorId}." event: NOT sending this out as $elapsed is less than interval of $mint");
                    }

                }
                else
                {
                    # This means we have no record of sending any event to this monitor
                    $last_sent->{$_->{MonitorId}} = time();
                    Info("Monitor ".$_->{MonitorId}." event: last time not found, so sending");
                    $_->{Cause} = $alarm_header if ($hook && $use_hook_description);
                    push (@localevents, $_);
                }

            }
            else 
            {
                Info ("Not sending alarm as Monitor ".$_->{MonitorId}." is excluded");
            }
            

        }
        # if this array is empty that means none of the alarms 
        # were generated from a monitor it is interested in
        next if (scalar @localevents == 0);

        my $str = encode_json({event => 'alarm', type=>'', status=>'Success', events => \@localevents});
        my $sup_str = encode_json({event => 'alarm', type=>'', status=>'Success', supplementary=>'true', events => \@localevents});
        my %hash_str = (event => 'alarm', status=>'Success', events => \@localevents);
        $i++;
        # if there is APNS send it over APNS
        # if not, send it over Websockets 
        # also disabled is a special state which means its registered over push
        # but it still wants messages over websockets - zmNinja sets this
        # when websockets override is enabled
        if (($_->{token} ne "") && ($_->{pushstate} ne "disabled" ) && ($_->{pending} != PENDING_WEBSOCKET))
        {
            if ($use_fcm)
            {
                Info ("Sending notification over FCM");  
                sendOverFCM($_,$alarm_header, $alarm_mid, $alarm_eid,$str, $alarm_monitor_name) ;     
            }
            
            # send supplementary event data over websocket
            if ($_->{pending} == VALID_WEBSOCKET)
            {
                if (exists $_->{conn})
                {
                    Info ($_->{conn}->ip()."-sending supplementary data over websockets\n");
                    eval {$_->{conn}->send_utf8($sup_str);};
                    if ($@)
                    {
            
                        printdbg ("Marking ".$_->{conn}->ip()." as INVALID_WEBSOCKET, as websocket send error with token:",$_->{token});     
                        $_->{pending} = INVALID_WEBSOCKET;

                    }
                }
            }

        }
            # if there is a websocket send it over websockets
            elsif ($_->{pending} == VALID_WEBSOCKET)
            {
                if (exists $_->{conn})
                {
                    Info ($_->{conn}->ip()."-sending over websockets\n");
                    eval {$_->{conn}->send_utf8($str);};
                    if ($@)
                    {
                
                        printdbg ("Marking ".$_->{conn}->ip()." as INVALID_WEBSOCKET, as websocket send error");     
                        $_->{pending} = INVALID_WEBSOCKET;
                    }
                }
            }
            

            
        }
    
}

# This is really the main module
# It opens a WSS socket and keeps listening
sub initSocketServer
{
    checkEvents();
    my $ssl_server;
    if ($ssl_enabled)
    {
        Info ("About to start listening to socket");
	eval {
  	       $ssl_server = IO::Socket::SSL->new(
		      Listen        => 10,
		      LocalPort     => $port,
		      LocalAddr => $address,
		      Proto         => 'tcp',
		      Reuse     => 1,
		      ReuseAddr     => 1,
		      SSL_cert_file => $ssl_cert_file,
		      SSL_key_file  => $ssl_key_file
		    );
	};
	if ($@) {
		printdbg("Failed starting server: $@");
		Error("Failed starting server: $@");
		exit(-1);
	}
                Info ("Secure WS(WSS) is enabled...");
    }
    else
    {
        Info ("Secure WS is disabled...");
    }
    Info ("Web Socket Event Server listening on port ".$port."\n");

    $wss = Net::WebSocket::Server->new(
        listen => $ssl_enabled ? $ssl_server : $port,
        tick_period => $event_check_interval,
        on_tick => sub {
            checkConnection();
            
            if (checkEvents())
            {
            
                Info ("Launching thread to handle alarm for:".$alarm_eid." monitor:".$alarm_mid);
                processAlarms();
                #threads->create ( sub {
                #   processAlarms();
                #    Info ("Terminating thread to handle alarm for:".$alarm_eid." monitor:".$alarm_mid);
                #   threads->detach();
                #});
                # disable forking for now
                # as child exit kills the socket

                #processAlarms();
                #my $pid = fork;
                #if (!defined $pid) {
                #    die "Cannot fork: $!";

                #}
                #elsif ($pid == 0) {
                #    # client
                #    local $SIG{'CHLD'} = 'DEFAULT';
                #    printdbg ("Forking process to handle alarm for:".$alarm_eid." monitor:".$alarm_mid);
                #    processAlarms();
                #    printdbg ("Ending process to handle alarm for:".$alarm_eid." monitor:".$alarm_mid);
                #    exit 0; 
                #}
                

            }
        },
        # called when a new connection comes in
        on_connect => sub {
            my ($serv, $conn) = @_;
            my ($len) = scalar @active_connections;
            Info ("got a websocket connection from ".$conn->ip()." (". $len.") active connections");
            $conn->on(
                utf8 => sub {
                    my ($conn, $msg) = @_;
		    Debug ("Raw incoming message: $msg");
            printdbg ("Raw incoming message: $msg");
                    checkMessage($conn, $msg);
                },
                handshake => sub {
                    my ($conn, $handshake) = @_;
                    printdbg ("HANDSHAKE: Websockets: New Connection Handshake requested from ".$conn->ip().":".$conn->port()." state=pending auth");
                    Info ("Websockets: New Connection Handshake requested from ".$conn->ip().":".$conn->port()." state=pending auth");
                    my $connect_time = time();
                    push @active_connections, {conn => $conn, 
                                   pending => PENDING_WEBSOCKET, 
                                   time=>$connect_time, 
                                   monlist => "",
                                   intlist => "",
                                   last_sent=>{},
                                   platform => "websocket",
                                   pushstate => '',
                                   badge => 0};
                   
                },
                disconnect => sub
                {
                    my ($conn, $code, $reason) = @_;
                    Info ("Websocket remotely disconnected from ".$conn->ip());
                    foreach (@active_connections)
                    {
                        if ((exists $_->{conn}) && ($_->{conn}->ip() eq $conn->ip())  &&
                                        ($_->{conn}->port() eq $conn->port()))
                        {
                            # mark this for deletion only if device token
                            # not present
                            if ( $_->{token} eq '')
                            {
                                $_->{pending}=INVALID_REMOTE;
                                Info( "Marking ".$conn->ip()." for deletion as websocket closed remotely\n");
                            }
                            else
                            {
                                
                                Info( "NOT Marking ".$conn->ip()." for deletion as token ".$_->{token}." active\n");
                            }
                        }

                    }
                },
            );

            
        }
    )->start;
}
