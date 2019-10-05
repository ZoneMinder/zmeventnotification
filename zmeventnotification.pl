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

use strict ;
use bytes ;
use POSIX ':sys_wait_h' ;
use Time::HiRes qw/gettimeofday/ ;
use Symbol qw(qualify_to_ref) ;
use IO::Select ;


# debugging only.
#use Data::Dumper;

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


my $app_version="4.4";


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

# configuration constants
use constant {
    DEFAULT_CONFIG_FILE       => "/etc/zm/zmeventnotification.ini",
    DEFAULT_PORT              => 9000,
    DEFAULT_ADDRESS           => '[::]',
    DEFAULT_AUTH_ENABLE       => 'yes',
    DEFAULT_AUTH_TIMEOUT      => 20,
    DEFAULT_FCM_ENABLE        => 'yes',
    DEFAULT_MQTT_ENABLE       => 'no',
    DEFAULT_MQTT_SERVER       => '127.0.0.1',
    DEFAULT_FCM_TOKEN_FILE    => '/var/lib/zmeventnotification/push/tokens.txt',
    DEFAULT_SSL_ENABLE        => 'yes',
    DEFAULT_CUSTOMIZE_VERBOSE => 'no',
    DEFAULT_CUSTOMIZE_EVENT_CHECK_INTERVAL          => 5,
    DEFAULT_CUSTOMIZE_MONITOR_RELOAD_INTERVAL       => 300,
    DEFAULT_CUSTOMIZE_READ_ALARM_CAUSE              => 'no',
    DEFAULT_CUSTOMIZE_TAG_ALARM_EVENT_ID            => 'no',
    DEFAULT_CUSTOMIZE_USE_CUSTOM_NOTIFICATION_SOUND => 'no',
    DEFAULT_CUSTOMIZE_INCLUDE_PICTURE               => 'no',
    DEFAULT_HOOK_KEEP_FRAME_MATCH_TYPE              => 'yes',
    DEFAULT_HOOK_USE_HOOK_DESCRIPTION               => 'no',
    DEFAULT_HOOK_STORE_FRAME_IN_ZM                  => 'no',
    } ;

# connection state
use constant {
    PENDING_AUTH       => 1,
    VALID_CONNECTION   => 2,
    INVALID_CONNECTION => 3,
    PENDING_DELETE     => 4,
    } ;

# connection types
use constant {
    FCM  => 1000,
    MQTT => 1001,
    WEB  => 1002
    } ;

# Declare options.

my $help ;

my $config_file ;
my $config_file_present ;
my $check_config ;

my $port ;
my $address ;

my $auth_enabled ;
my $auth_timeout ;

my $use_mqtt ;
my $mqtt_server ;
my $mqtt_username ;
my $mqtt_password ;

my $use_fcm ;
my $fcm_api_key ;
my $token_file ;

my $ssl_enabled ;
my $ssl_cert_file ;
my $ssl_key_file ;

my $console_logs ;
my $event_check_interval ;
my $monitor_reload_interval ;
my $read_alarm_cause ;
my $tag_alarm_event_id ;
my $use_custom_notification_sound ;

my $hook ;
my $use_hook_description ;
my $keep_frame_match_type ;
my $skip_monitors ;
my $hook_pass_image_path ;

my $picture_url ;
my $include_picture ;
my $picture_portal_username;
my $picture_portal_password;

#default key. Please don't change this
use constant NINJA_API_KEY =>
    "AAAApYcZ0mA:APA91bG71SfBuYIaWHJorjmBQB3cAN7OMT7bAxKuV3ByJ4JiIGumG6cQw0Bo6_fHGaWoo4Bl-SlCdxbivTv5Z-2XPf0m86wsebNIG15pyUHojzmRvJKySNwfAHs7sprTGsA_SIR_H43h"
    ;

my $dummyEventTest = 0
    ; # if on, will generate dummy events. Not in config for a reason. Only dev testing
my $dummyEventInterval     = 20 ;       # timespan to generate events in seconds
my $dummyEventTimeLastSent = time() ;

# This part makes sure we have the right core deps. See later for optional deps

if ( !try_use( "Net::WebSocket::Server" ) ) {
    Fatal( "Net::WebSocket::Server missing" ) ;
    }
if ( !try_use( "IO::Socket::SSL" ) )  { Fatal( "IO::Socket::SSL missing" ) ; }
if ( !try_use( "IO::Handle" ) )       { Fatal( "IO::Handle" ) ; }
if ( !try_use( "Config::IniFiles" ) ) { Fatal( "Config::Inifiles missing" ) ; }
if ( !try_use( "Getopt::Long" ) )     { Fatal( "Getopt::Long missing" ) ; }
if ( !try_use( "File::Basename" ) )   { Fatal( "File::Basename missing" ) ; }
if ( !try_use( "File::Spec" ) )       { Fatal( "File::Spec missing" ) ; }
if ( !try_use( "URI::Escape" ) )       { Fatal( "URI::Escape missing" ) ; }


#if (!try_use ("threads")) {Fatal ("threads library/support  missing");}

use constant USAGE => <<'USAGE';

Usage: zmeventnotification.pl [OPTION]...

  --help                              Print this page.

  --config=FILE                       Read options from configuration file (default: /etc/zm/zmeventnotification.ini).
                                      Any CLI options used below will override config settings.

  --check-config                      Print configuration and exit.

USAGE

GetOptions(
    "help" => \$help,

    "config=s"     => \$config_file,
    "check-config" => \$check_config,
    ) ;

exit( print( USAGE ) ) if $help ;

# Read options from a configuration file.  If --config is specified, try to
# read it and fail if it can't be read.  Otherwise, try the default
# configuration path, and if it doesn't exist, take all the default values by
# loading a blank Config::IniFiles object.

if ( !$config_file ) {
    $config_file         = DEFAULT_CONFIG_FILE ;
    $config_file_present = -e $config_file ;
    }
else {
    if ( !-e $config_file ) {
        Fatal( "$config_file does not exist!" ) ;
        }
    $config_file_present = 1 ;
    }

my $config ;

if ( $config_file_present ) {
    printInfo( "using config file: $config_file" ) ;
    $config = Config::IniFiles->new( -file => $config_file ) ;

    unless ( $config ) {
        Fatal( "Encountered errors while reading $config_file:\n"
                . join( "\n", @Config::IniFiles::errors ) ) ;
        }
    }
else {
    $config = Config::IniFiles->new ;
    printInfo( "No config file found, using inbuilt defaults" ) ;
    }

# If an option set a value, leave it.  If there's a value in the config, use
# it.  Otherwise, use a default value if it's available.

$port    //= config_get_val( $config, "network", "port",    DEFAULT_PORT ) ;
$address //= config_get_val( $config, "network", "address", DEFAULT_ADDRESS ) ;

$auth_enabled //=
    config_get_val( $config, "auth", "enable", DEFAULT_AUTH_ENABLE ) ;
$auth_timeout //=
    config_get_val( $config, "auth", "timeout", DEFAULT_AUTH_TIMEOUT ) ;

$use_mqtt //= config_get_val( $config, "mqtt", "enable", DEFAULT_MQTT_ENABLE ) ;
$mqtt_server //=
    config_get_val( $config, "mqtt", "server", DEFAULT_MQTT_SERVER ) ;
$mqtt_username //= config_get_val( $config, "mqtt", "username" ) ;
$mqtt_password //= config_get_val( $config, "mqtt", "password" ) ;

$use_fcm //= config_get_val( $config, "fcm", "enable", DEFAULT_FCM_ENABLE ) ;
$fcm_api_key //= config_get_val( $config, "fcm", "api_key", NINJA_API_KEY ) ;
$token_file //=
    config_get_val( $config, "fcm", "token_file", DEFAULT_FCM_TOKEN_FILE ) ;

$ssl_enabled //=
    config_get_val( $config, "ssl", "enable", DEFAULT_SSL_ENABLE ) ;
$ssl_cert_file //= config_get_val( $config, "ssl", "cert" ) ;
$ssl_key_file  //= config_get_val( $config, "ssl", "key" ) ;

$console_logs //= config_get_val( $config, "customize", "console_logs",
    DEFAULT_CUSTOMIZE_VERBOSE ) ;
$event_check_interval //=
    config_get_val( $config, "customize", "event_check_interval",
    DEFAULT_CUSTOMIZE_EVENT_CHECK_INTERVAL ) ;
$monitor_reload_interval //=
    config_get_val( $config, "customize", "monitor_reload_interval",
    DEFAULT_CUSTOMIZE_MONITOR_RELOAD_INTERVAL ) ;
$read_alarm_cause //= config_get_val( $config, "customize", "read_alarm_cause",
    DEFAULT_CUSTOMIZE_READ_ALARM_CAUSE ) ;
$tag_alarm_event_id //=
    config_get_val( $config, "customize", "tag_alarm_event_id",
    DEFAULT_CUSTOMIZE_TAG_ALARM_EVENT_ID ) ;
$use_custom_notification_sound //= config_get_val(
    $config, "customize",
    "use_custom_notification_sound",
    DEFAULT_CUSTOMIZE_USE_CUSTOM_NOTIFICATION_SOUND
    ) ;
$picture_url //= config_get_val( $config, "customize", "picture_url" ) ;
$include_picture //= config_get_val( $config, "customize", "include_picture",
    DEFAULT_CUSTOMIZE_INCLUDE_PICTURE ) ;

$picture_portal_username //= config_get_val( $config, "customize", "picture_portal_username" ) ;
$picture_portal_password //= config_get_val( $config, "customize", "picture_portal_password" ) ;

$hook //= config_get_val( $config, "hook", "hook_script" ) ;
$use_hook_description //=
    config_get_val( $config, "hook", "use_hook_description",
    DEFAULT_HOOK_USE_HOOK_DESCRIPTION ) ;
$keep_frame_match_type //=
    config_get_val( $config, "hook", "keep_frame_match_type",
    DEFAULT_HOOK_KEEP_FRAME_MATCH_TYPE ) ;
$skip_monitors //= config_get_val( $config, "hook", "skip_monitors" ) ;
$hook_pass_image_path //=
    config_get_val( $config, "hook", "hook_pass_image_path" ) ;

my %ssl_push_opts = () ;

if ( $ssl_enabled && ( !$ssl_cert_file || !$ssl_key_file ) ) {
    Fatal( "SSL is enabled, but key or certificate file is missing" ) ;
    }

my $notId = 1 ;

# this is just a wrapper around Config::IniFiles val
# older versions don't support a default parameter
sub config_get_val {
    my ( $config, $sect, $parm, $def ) = @_ ;
    my $val = $config->val( $sect, $parm ) ;

    my $final_val = defined( $val ) ? $val : $def ;

    # compatibility hack, lets use yes/no in config to maintain
    # parity with hook config
    if    ( lc( $final_val ) eq 'yes' ) { $final_val = 1 ; }
    elsif ( lc( $final_val ) eq 'no' )  { $final_val = 0 ; }
    return $final_val ;
    }

# helper routines to print config status in help
sub yes_or_no {
    return $_[ 0 ] ? "yes" : "no" ;
    }

sub value_or_undefined {
    return $_[ 0 ] || "(undefined)" ;
    }

sub present_or_not {
    return $_[ 0 ] ? "(defined)" : "(undefined)" ;
    }

sub print_config {
    my $abs_config_file = File::Spec->rel2abs( $config_file ) ;

    print(
        <<"EOF"

${\(
  $config_file_present ?
  "Configuration (read $abs_config_file)" :
  "Default configuration ($abs_config_file doesn't exist)"
)}:

Port .......................... ${\(value_or_undefined($port))}
Address ....................... ${\(value_or_undefined($address))}
Event check interval .......... ${\(value_or_undefined($event_check_interval))}
Monitor reload interval ....... ${\(value_or_undefined($monitor_reload_interval))}

Auth enabled .................. ${\(yes_or_no($auth_enabled))}
Auth timeout .................. ${\(value_or_undefined($auth_timeout))}

Use FCM ....................... ${\(yes_or_no($use_fcm))}
FCM API key ................... ${\(present_or_not($fcm_api_key))}
Token file .................... ${\(value_or_undefined($token_file))}

Use MQTT .......................${\(yes_or_no($use_mqtt))}
MQTT Server ....................${\(value_or_undefined($mqtt_server))}
MQTT Username ..................${\(value_or_undefined($mqtt_username))}
MQTT Password ..................${\(present_or_not($mqtt_password))}

SSL enabled ................... ${\(yes_or_no($ssl_enabled))}
SSL cert file ................. ${\(value_or_undefined($ssl_cert_file))}
SSL key file .................. ${\(value_or_undefined($ssl_key_file))}

Verbose ....................... ${\(yes_or_no($console_logs))}
Read alarm cause .............. ${\(yes_or_no($read_alarm_cause))}
Tag alarm event id ............ ${\(yes_or_no($tag_alarm_event_id))}
Use custom notification sound . ${\(yes_or_no($use_custom_notification_sound))}

Hook .......................... ${\(value_or_undefined($hook))}
Use Hook Description........... ${\(yes_or_no($use_hook_description))}
Keep frame match type.......... ${\(yes_or_no($keep_frame_match_type))}
Skipped monitors............... ${\(value_or_undefined($skip_monitors))}
Store Frame in ZM...............${\(yes_or_no($hook_pass_image_path))}


Picture URL ................... ${\(value_or_undefined($picture_url))}
Include picture................ ${\(yes_or_no($include_picture))}
Picture username .............. ${\(value_or_undefined($picture_portal_username))}
Picture password .............. ${\(present_or_not($picture_portal_password))}

EOF
        );
    }

exit( print_config() ) if $check_config ;
print_config() if $console_logs ;

# Lets now load all the optional dependent libraries in a failsafe way

if ( !try_use( "JSON" ) ) {
    if ( !try_use( "JSON::XS" ) ) {
        Fatal( "JSON or JSON::XS  missing" ) ;
        exit( -1 ) ;
        }
    }

# Fetch whatever options are available from CLI arguments.

if ( $use_fcm ) {
    if (   !try_use( "LWP::UserAgent" )
        || !try_use( "URI::URL" )
        || !try_use( "LWP::Protocol::https" ) ) {
        Fatal(
            "FCM push mode needs LWP::Protocol::https, LWP::UserAgent and URI::URL perl packages installed"
            ) ;
        }
    else {
        printInfo( "Push enabled via FCM" ) ;
        }

    }
else {
    printInfo( "FCM disabled. Will only send out websocket notifications" ) ;
    }

if ( $use_mqtt ) {
    if ( !try_use( "Net::MQTT::Simple" ) ) {
        Fatal( "Net::MQTT::Simple  missing" ) ;
        exit( -1 ) ;
        }
    printInfo( "MQTT Enabled" ) ;

    }
else {
    printInfo( "MQTT Disabled" ) ;
    }

# ==========================================================================
#
# Don't change anything below here
#
# ==========================================================================

use ZoneMinder ;
use POSIX ;
use DBI ;

$SIG{ CHLD } = 'IGNORE' ;

$ENV{ PATH } = '/bin:/usr/bin' ;
$ENV{ SHELL } = '/bin/sh' if exists $ENV{ SHELL } ;
delete @ENV{ qw(IFS CDPATH ENV BASH_ENV) } ;

sub Usage {
    print( "This daemon is not meant to be invoked from command line\n" ) ;
    exit( -1 ) ;
    }

# https://docstore.mik.ua/orelly/perl4/cook/ch07_24.htm
sub sysreadline(*;$) {
    my ( $handle, $timeout ) = @_ ;
    $handle = qualify_to_ref( $handle, caller() ) ;
    my $infinitely_patient = ( @_ == 1 || $timeout < 0 ) ;
    my $start_time         = time() ;
    my $selector           = IO::Select->new() ;
    $selector->add( $handle ) ;
    my $line = "" ;
SLEEP:

    until ( at_eol( $line ) ) {
        unless ( $infinitely_patient ) {
            return $line if time() > ( $start_time + $timeout ) ;
            }

        # sleep only 1 second before checking again
        next SLEEP unless $selector->can_read( 1.0 ) ;
    INPUT_READY:
        while ( $selector->can_read( 0.0 ) ) {
            my $was_blocking = $handle->blocking( 0 ) ;
        CHAR: while ( sysread( $handle, my $nextbyte, 1 ) ) {
                $line .= $nextbyte ;
                last CHAR if $nextbyte eq "\n" ;
                }
            $handle->blocking( $was_blocking ) ;

            # if incomplete line, keep trying
            next SLEEP unless at_eol( $line ) ;
            last INPUT_READY;
            }
        }
    return $line ;
    }
sub at_eol($) { $_[ 0 ] =~ /\n\z/ }

logInit() ;
logSetSignal() ;

my $dbh = zmDbConnect() ;
my %monitors ;
my %last_event_for_monitors ;
my $monitor_reload_time = 0 ;
my $apns_feedback_time  = 0 ;
my $proxy_reach_time    = 0 ;
my $wss ;
my @events             = () ;
my @active_connections = () ;
my @needsReload        = () ;

# Main entry point

printInfo( "You are running version: $app_version" ) ;
printWarning(
    "WARNING: SSL is disabled, which means all traffic will be unencrypted" )
    unless $ssl_enabled ;

pipe( READER, WRITER ) || die "pipe failed: $!" ;
WRITER->autoflush( 1 ) ;
my ( $rin, $rout ) = ( '' ) ;
vec( $rin, fileno( READER ), 1 ) = 1 ;
printDebug( "Parent<--Child pipe ready" ) ;

if ( $use_fcm ) {
    my $dir = dirname( $token_file ) ;
    if ( !-d $dir ) {

        printInfo( "Creating $dir to store FCM tokens" ) ;
        mkdir $dir ;
        }
    }

printInfo( "Event Notification daemon v $app_version starting\n" ) ;
loadPredefinedConnections() ;
initSocketServer() ;
printInfo( "Event Notification daemon exiting\n" ) ;
exit() ;

# Try to load a perl module
# and if it is not available
# generate a log

sub try_use {
    my $module = shift ;
    eval( "use $module" ) ;
    return ( $@ ? 0 : 1 ) ;
    }

# ZM logger print and optionally console print
sub printDebug {
    my $str = shift ;
    my $now = strftime( '%Y-%m-%d,%H:%M:%S', localtime ) ;
    print( 'CONSOLE DEBUG:', $now, " ", $str, "\n" ) if $console_logs ;
    Debug( $str ) ;
    }

sub printInfo {
    my $str = shift ;
    my $now = strftime( '%Y-%m-%d,%H:%M:%S', localtime ) ;
    print( 'CONSOLE INFO:', $now, " ", $str, "\n" ) if $console_logs ;
    Info( $str ) ;
    }

sub printWarning {
    my $str = shift ;
    my $now = strftime( '%Y-%m-%d,%H:%M:%S', localtime ) ;
    print( 'CONSOLE WARNING:', $now, " ", $str, "\n" ) if $console_logs ;
    Warning( $str ) ;
    }

sub printError {
    my $str = shift ;
    my $now = strftime( '%Y-%m-%d,%H:%M:%S', localtime ) ;
    print( 'CONSOLE ERROR:', $now, " ", $str, "\n" ) if $console_logs ;
    Error( $str ) ;
    }

# This function uses shared memory polling to check if
# ZM reported any new events. If it does find events
# then the details are packaged into the events array
# so they can be JSONified and sent out

# Output:
# a) List of events in the @events array with the following structure per event:
#    {Name => Name of monitor, MonitorId => ID of monitor, EventId => Event ID, Cause=> Cause text of alarm}
# b) A CONCATENATED list of events in $alarm_header_display for convenience
# c) A CONCATENATED list of monitor IDs in $alarm_mid

sub checkNewEvents() {

    my $eventFound = 0 ;
    if ( ( time() - $monitor_reload_time ) > $monitor_reload_interval ) {
        my $len = scalar @active_connections ;
        printInfo( "Total event client connections: " . $len . "\n" ) ;
        my $ndx = 1 ;
        foreach ( @active_connections ) {

            my $cip = "(none)" ;
            if ( exists $_->{ conn } ) {
                $cip = $_->{ conn }->ip() ;
                }
            printDebug( "-->checkNewEvents: Connection $ndx: ID->"
                    . $_->{ id } . " IP->"
                    . $cip
                    . " Token->:..."
                    . substr( $_->{ token }, -10 )
                    . " Plat:"
                    . $_->{ platform }
                    . " Push:"
                    . $_->{ pushstate } ) ;
            $ndx++ ;
            }
        printInfo( "Reloading Monitors...\n" ) ;
        foreach my $monitor ( values( %monitors ) ) {
            zmMemInvalidate( $monitor ) ;
            }
        loadMonitors() ;
        
        }
    elsif ( @needsReload ) {
        my @failedReloads = ();
        while (@needsReload) {
          my $monitor = shift @needsReload;
          if (!loadMonitor($monitor)) {
            printError ('Failed re-loading monitor:'.$monitor->{Id}.' adding back to reload list for next iteration');
            push(@failedReloads, $monitor);
          }
        }
        @needsReload = @failedReloads;
    }

    @events = () ;

    foreach my $monitor ( values( %monitors ) ) {
        my $alarm_cause = "" ;
        if ( !zmMemVerify( $monitor ) ) {

          #printDebug ('Monitor '.$monitor->{ Id }.' memverify FAILED');
# Our attempt to verify the memory handle failed. We should reload the monitors.
# Don't need to zmMemInvalidate because the monitor reload will do it.
            push @needsReload, $monitor ;
            Warning(  " Memory verify failed for "
                    . $monitor->{ Name } . "(id:"
                    . $monitor->{ Id }
                    . ")" ) ;
            next ;
            }
          else {
            #printDebug ('Monitor '.$monitor->{ Id }.' memverify is ok');
          }

        my ( $state, $last_event, $trigger_cause, $trigger_text ) = zmMemRead(
            $monitor,
            [
                "shared_data:state",          "shared_data:last_event",
                "trigger_data:trigger_cause", "trigger_data:trigger_text",
                ]
            ) ;

      # The alarm may have moved from ALARM to ALERT by the time ES got to it...
        if ( $state == STATE_ALARM || $state == STATE_ALERT ) {
            if (
                !defined( $monitor->{ LastEvent } )
                || ( $last_event !=
                    $last_event_for_monitors{ $monitor->{ Id } }{ "eid" } )
                    ) {
# It is possible we missed STATE_IDLE due to b2b events, so we may need to process it here
# as well

                if ( $last_event_for_monitors{ $monitor->{ Id } }{ "state" } eq
                    "recording" ) {
                    my $hooktext = $last_event_for_monitors{ $monitor->{ Id } }
                        { "hook_text" } ;
                    if ( $hooktext ) {
                        printDebug( "HOOK: (concurrent-event) "
                                . $last_event_for_monitors{ $monitor->{ Id } }
                                { "eid" }
                                . " writing hook to DB with hook text="
                                . $hooktext ) ;
                        updateEventinZmDB(
                            $last_event_for_monitors{ $monitor->{ Id } }
                                { "eid" },
                            $hooktext
                            )
                            if $hooktext ;
                        $last_event_for_monitors{ $monitor->{ Id } }
                            { "hook_text" } = undef ;
                        }

                    }
                $alarm_cause = zmMemRead( $monitor, "shared_data:alarm_cause" )
                    if ( $read_alarm_cause ) ;
                $alarm_cause = $trigger_cause
                    if ( defined( $trigger_cause )
                    && $alarm_cause eq ""
                    && $trigger_cause ne "" ) ;
                printInfo("New event $last_event reported for Monitor:"
                        . $monitor->{ Id }
                        . " (Name:"
                        . $monitor->{ Name } . ") "
                        . $alarm_cause
                        . "\n" ) ;
                $monitor->{ LastState } = $state ;
                $monitor->{ LastEvent } = $last_event ;
                $last_event_for_monitors{ $monitor->{ Id } }{ "eid" } =
                    $last_event ;
                $last_event_for_monitors{ $monitor->{ Id } }{ "state" } =
                    "recording" ;
                my $name = $monitor->{ Name } ;
                my $mid  = $monitor->{ Id } ;
                my $eid  = $last_event ;
                printDebug( "HOOK: $last_event Creating event object for "
                        . $monitor->{ Name }
                        . ", setting state to recording" ) ;
                push @events,
                    {
                    Name      => $name,
                    MonitorId => $mid,
                    EventId   => $last_event,
                    Cause     => $alarm_cause
                    } ;
                $eventFound = 1 ;
                }

            }
        elsif ($state == STATE_IDLE
            && $last_event_for_monitors{ $monitor->{ Id } }{ "state" } eq
            "recording" ) {
            my $hooktext =
                $last_event_for_monitors{ $monitor->{ Id } }{ "hook_text" } ;
            printDebug( "Alarm "
                    . $monitor->{ LastEvent }
                    . " for monitor:"
                    . $monitor->{ Id }
                    . " has ended "
                    . $hooktext ) ;
            if ( $hooktext ) {
                printDebug( "HOOK: "
                        . $monitor->{ LastEvent }
                        . " writing hook to DB with hook text="
                        . $hooktext ) ;
                }
            else {
                printDebug( "HOOK: "
                        . $monitor->{ LastEvent }
                        . " NOT writing hook to DB as hook text was empty" ) ;
                }
            updateEventinZmDB( $monitor->{ LastEvent }, $hooktext )
                if $hooktext ;
            $last_event_for_monitors{ $monitor->{ Id } }{ "state" } = "idle" ;
            $last_event_for_monitors{ $monitor->{ Id } }{ "hook_text" } =
                undef ;

            }
        }
    printDebug( "checkEvents() events found=$eventFound" ) ;

    # Send out dummy events for testing
    if (  !$eventFound
        && $dummyEventTest
        && ( time() - $dummyEventTimeLastSent ) >= $dummyEventInterval ) {
        $dummyEventTimeLastSent = time() ;
        my $random_mon1 =
            $monitors{ ( keys %monitors )[ rand keys %monitors ] } ;
        my $random_mon2 =
            $monitors{ ( keys %monitors )[ rand keys %monitors ] } ;
        printInfo( "Sending dummy event to: " . $random_mon1->{ Name } ) ;

        #printInfo ("Sending dummy event to: ".$random_mon2->{Name});
        push @events,
            {
            Name      => $random_mon1->{ Name },
            MonitorId => $random_mon1->{ Id },
            EventId   => $random_mon1->{ LastEvent },
            Cause     => "Dummy1"
            } ;
        push @events,
            {
            Name      => $random_mon2->{ Name },
            MonitorId => $random_mon2->{ Id },
            EventId   => $random_mon2->{ LastEvent },
            Cause     => "Dummy2"
            } ;

        $eventFound = 1 ;

        }

    return ( $eventFound ) ;
    }

sub loadMonitor {
    my $monitor = shift ;
    printInfo( "loadMonitor: re-loading monitor " . $monitor->{ Name } ) ;
    zmMemInvalidate( $monitor ) ;
    if ( zmMemVerify( $monitor ) ) {    # This will re-init shared memory
        $monitor->{ LastState } = zmGetMonitorState( $monitor ) ;
        $monitor->{ LastEvent } = zmGetLastEvent( $monitor ) ;
        return 1;
    }
    return 0; # coming here means verify failed
  }

# Refreshes list of monitors from DB
#
sub loadMonitors {
    printInfo( "Re-loading monitors, emptying needsReload() list\n" ) ;
    @needsReload = () ;
    $monitor_reload_time = time() ;

    my %new_monitors = () ;

    my $sql = "SELECT * FROM Monitors
        WHERE find_in_set( Function, 'Modect,Mocord,Nodect' )"
        . ( $Config{ ZM_SERVER_ID } ? 'AND ServerId=?' : '' ) ;
    my $sth = $dbh->prepare_cached( $sql )
        or Fatal( "Can't prepare '$sql': " . $dbh->errstr() ) ;
    my $res =
        $sth->execute( $Config{ ZM_SERVER_ID } ? $Config{ ZM_SERVER_ID } : () )
        or Fatal( "Can't execute: " . $sth->errstr() ) ;
    while ( my $monitor = $sth->fetchrow_hashref() ) {

        if ( zmMemVerify( $monitor ) ) {
            $monitor->{ LastState } = zmGetMonitorState( $monitor ) ;
            $monitor->{ LastEvent } = zmGetLastEvent( $monitor ) ;
       	    $new_monitors{ $monitor->{ Id } } = $monitor ;
            }
	    else {
          printError ("loadMonitors: zmMemVerify for monitor:".$monitor->{Id}." failed, setting up for reload in next iteration");
          push @needsReload, $monitor;

	    }
        }    # end while fetchrow
    %monitors = %new_monitors ;
    }

# Updated Notes DB of events with detection text
# if available (hook enabled)
sub updateEventinZmDB {
    my ( $eid, $notes ) = @_ ;
    $notes = $notes . " " ;
    printDebug(
        "updating Notes clause for Event:" . $eid . " with:" . $notes ) ;
    my $sql = "UPDATE Events set Notes=CONCAT(?,Notes) where Id=?" ;
    my $sth = $dbh->prepare_cached( $sql )
        or Fatal( "HOOK: Can't prepare '$sql': " . $dbh->errstr() ) ;
    my $res = $sth->execute( $notes, $eid )
        or Fatal( "HOOK: Can't execute: " . $sth->errstr() ) ;
    }

# This function compares the password provided over websockets
# to the password stored in the ZM MYSQL DB

sub validateZmAuth {
    return 1 unless $auth_enabled ;
    my ( $u, $p ) = @_ ;
    return 0 if ( $u eq "" || $p eq "" ) ;
    my $sql = 'select Password from Users where Username=?' ;
    my $sth = $dbh->prepare_cached( $sql )
        or Fatal( "Can't prepare '$sql': " . $dbh->errstr() ) ;
    my $res = $sth->execute( $u )
        or Fatal( "Can't execute: " . $sth->errstr() ) ;
    if ( my ( $state ) = $sth->fetchrow_hashref() ) {
        my $scheme = substr( $state->{ Password }, 0, 1 ) ;
        if ( $scheme eq "*" ) {    # mysql decode
            printDebug( "Comparing using mysql hash" ) ;
            if ( !try_use( "Crypt::MySQL qw(password password41)" ) ) {
                Fatal( "Crypt::MySQL  missing, cannot validate password" ) ;
                return 0 ;
                }
            my $encryptedPassword = password41( $p ) ;
            $sth->finish() ;
            return $state->{ Password } eq $encryptedPassword ;
            }
        else {                     # try bcrypt
            if ( !try_use( "Crypt::Eksblowfish::Bcrypt" ) ) {
                Fatal(
                    "Crypt::Eksblowfish::Bcrypt missing, cannot validate password"
                    ) ;
                return 0 ;
                }
            my $saved_pass = $state->{ Password } ;

            # perl bcrypt libs can't handle $2b$ or $2y$
            $saved_pass =~ s/^\$2.\$/\$2a\$/ ;
            my $new_hash =
                Crypt::Eksblowfish::Bcrypt::bcrypt( $p, $saved_pass ) ;
            printDebug( "Comparing using bcrypt $new_hash to $saved_pass" ) ;
            return $new_hash eq $saved_pass ;
            }
        }
    else {
        $sth->finish() ;
        return 0 ;
        }

    }

# deletes a token - invoked if FCM responds with an incorrect token error
sub deleteFCMToken {
    my $dtoken = shift ;
    printDebug( "DeleteToken called with ..." . substr( $dtoken, -10 ) ) ;
    return if ( !-f $token_file ) ;

    open( my $fh, '<', $token_file ) ;
    chomp( my @lines = <$fh> ) ;
    close( $fh ) ;
    my @uniquetokens = uniq( @lines ) ;

    open( $fh, '>', $token_file ) ;

    foreach ( @uniquetokens ) {
        my ( $token, $monlist, $intlist, $platform, $pushstate ) =
            rsplit( qr/:/, $_, 5 ) ;    #split (":",$_);
        next if ( $_ eq "" || $token eq $dtoken ) ;
        print $fh "$_\n" ;

        #print "delete: $row\n";
        my $tod = gettimeofday ;
        push @active_connections,
            {
            type         => FCM,
            id           => $tod,
            token        => $token,
            state        => INVALID_CONNECTION,
            time         => time(),
            badge        => 0,
            monlist      => $monlist,
            intlist      => $intlist,
            last_sent    => {},
            platform     => $platform,
            pushstate    => $pushstate,
            extra_fields => ''
            } ;

        }
    close( $fh ) ;
    }

# Sends a push notification to the mqtt Broker
sub sendOverMQTTBroker {

    my $alarm = shift ;
    my $ac    = shift ;
    my $json ;

# only remove if not removed before. If you are sending over multiple channels, it may have already been stripped
    $alarm->{ Cause } = substr( $alarm->{ Cause }, 4 )
        if ( !$keep_frame_match_type && $alarm->{ Cause } =~ /^\[.\]/ ) ;
    my $description =
          $alarm->{ Name } . ":("
        . $alarm->{ EventId } . ") "
        . $alarm->{ Cause } ;

    $json = encode_json( {
            monitor => $alarm->{ MonitorId },
            name    => $description,
            state   => 'alarm',
            eventid => $alarm->{ EventId }
            }
        ) ;

    # based on the library docs, if this fails, it will try and reconnect
    # before the next message is sent (with a retry timer of 5 s)
    $ac->{ mqtt_conn }
        ->publish( join( '/', 'zoneminder', $alarm->{ MonitorId } ) => $json ) ;

    }

sub sendOverWebSocket {

# We can't send websocket data in a fork. WSS contains user space crypt data that
# goes out of sync with the parent. So we use a parent pipe
    my $alarm = shift ;
    my $ac    = shift ;

# only remove if not removed before. If you are sending over multiple channels, it may have already been stripped
    $alarm->{ Cause } = substr( $alarm->{ Cause }, 4 )
        if ( !$keep_frame_match_type && $alarm->{ Cause } =~ /^\[.\]/ ) ;
    my $str = encode_json( {
            event  => 'alarm',
            type   => '',
            status => 'Success',
            events => [ $alarm ]
            }
        ) ;
    printDebug( "Child: posting job to send out message to id:"
            . $ac->{ id } . "->"
            . $ac->{ conn }->ip() . ":"
            . $ac->{ conn }->port() ) ;
    print WRITER "message--TYPE--" . $ac->{ id } . "--SPLIT--" . $str . "\n" ;

    }

# Sends a push notification to FCM
sub sendOverFCM {

    my $alarm = shift ;
    my $obj   = shift ;
    my $mid   = $alarm->{ MonitorId } ;
    my $eid   = $alarm->{ EventId } ;
    my $mname = $alarm->{ Name } ;

    my $pic = $picture_url =~ s/EVENTID/$eid/gr ;
    $pic = $pic.'&username='.$picture_portal_username if ($picture_portal_username);
    $pic = $pic.'&password='.uri_escape($picture_portal_password) if ($picture_portal_password);
    #printInfo ("Using URL: $pic with password=$picture_portal_password");

    # if we used best match we will use the right image in notification
    if ( substr( $alarm->{ Cause }, 0, 3 ) eq "[a]" ) {
        my $npic = $pic =~ s/BESTMATCH/alarm/gr ;
        $pic = $npic ;
        printDebug( "Alarm frame matched, changing picture url to:$pic " ) ;
        $alarm->{ Cause } = substr( $alarm->{ Cause }, 4 )
            if ( !$keep_frame_match_type ) ;
        }

    elsif ( substr( $alarm->{ Cause }, 0, 3 ) eq "[s]" ) {
        my $npic = $pic =~ s/BESTMATCH/snapshot/gr ;
        $pic = $npic ;
        printDebug( "Alarm frame matched, changing picture url to:$pic " ) ;
        $alarm->{ Cause } = substr( $alarm->{ Cause }, 4 )
            if ( !$keep_frame_match_type ) ;
        }
    elsif ( substr( $alarm->{ Cause }, 0, 3 ) eq "[x]" ) {
        $alarm->{ Cause } = substr( $alarm->{ Cause }, 4 )
            if ( !$keep_frame_match_type ) ;
        }

    my $now   = strftime( '%I:%M %p, %d-%b', localtime ) ;
    my $body  = $alarm->{ Cause } . " at " . $now ;
    my $badge = $obj->{ badge } + 1 ;

    print WRITER "badge--TYPE--" . $obj->{ id } . "--SPLIT--" . $badge . "\n" ;
    my $uri = "https://fcm.googleapis.com/fcm/send" ;
    my $json ;

    # use zmNinja FCM key if the user did not override
    my $key   = "key=" . $fcm_api_key ;
    my $title = $mname . " Alarm" ;
    $title = $title . " (" . $eid . ")" if ( $tag_alarm_event_id ) ;

    my $ios_message = {
        to           => $obj->{ token },
        notification => {
            title => $title,
            body  => $body,
            sound => "default",
            badge => $badge,
            },
        data => {
            myMessageId => $notId,
            mid         => $mid,
            eid         => $eid,
            summaryText => "$eid"
            }
            } ;

    my $android_message = {
        to       => $obj->{ token },
        priority => 'high',
        data     => {
            title       => $title,
            message     => $body,
            style       => "inbox",
            myMessageId => $notId,
            icon        => "ic_stat_notification",
            mid         => $mid,
            eid         => $eid,
            badge       => $obj->{ badge },
            priority    => 1
            }
            } ;

    if ( $picture_url && $include_picture ) {
        $ios_message->{ 'mutable_content' } = \1 ;

        #$ios_message->{'content_available'} = \1;
        $ios_message->{ 'data' }->{ 'image_url_jpg' } = $pic ;

        $android_message->{ 'data' }->{ 'style' }       = 'picture' ;
        $android_message->{ 'data' }->{ 'picture' }     = $pic ;
        $android_message->{ 'data' }->{ 'summaryText' } = 'alarmed image' ;

        #printDebug ("Alarm image for android will be: $pic");
        }

    if ( $obj->{ platform } eq "ios" ) {
        $json = encode_json( $ios_message ) ;
        }

    # if I do both, notification icon in Android gets messed up
    else {    # android
        $json  = encode_json( $android_message ) ;
        $notId = ( $notId + 1 ) % 100000 ;

        }

    printDebug( "Final JSON being sent is: $json" ) ;
    my $req = HTTP::Request->new( 'POST', $uri ) ;
    $req->header(
        'Content-Type'  => 'application/json',
        'Authorization' => $key
        ) ;
    $req->content( $json ) ;
    my $lwp = LWP::UserAgent->new( %ssl_push_opts ) ;
    my $res = $lwp->request( $req ) ;
    my $msg ;
    my $json_string ;

    if ( $res->is_success ) {
        $msg = $res->decoded_content ;
        printInfo(
            "FCM push message returned a 200 with body " . $res->content ) ;
        eval { $json_string = decode_json( $msg ) ; } ;
        if ( $@ ) {

            Error( "Failed decoding sendFCM Response: $@" ) ;
            return ;
            }
        if ( $json_string->{ 'failure' } eq 1 ) {
            my $reason = $json_string->{ 'results' }[ 0 ]->{ 'error' } ;
            Error( "Error sending FCM for token:" . $obj->{ token } ) ;
            Error( "Error value =" . $reason ) ;
            if (   $reason eq "NotRegistered"
                || $reason eq "InvalidRegistration" ) {
                printInfo( "Removing this token as FCM doesn't recognize it" ) ;
                deleteFCMToken( $obj->{ token } ) ;
                }

            }
        }
    else {
        printInfo( "FCM push message Error:" . $res->status_line ) ;
        }

    # send supplementary event data over websocket, same SSL state issue
    # so use a parent pipe
    if ( $obj->{ state } == VALID_CONNECTION && exists $obj->{ conn } ) {
        my $sup_str = encode_json( {
                event         => 'alarm',
                type          => '',
                status        => 'Success',
                supplementary => 'true',
                events        => [ $alarm ]
                }
            ) ;
        print WRITER "message--TYPE--"
            . $obj->{ id }
            . "--SPLIT--"
            . $sup_str
            . "\n" ;

        }

    }

# credit: https://stackoverflow.com/a/52724546/1361529
sub processJobs {
    while (
        ( my $read_avail = select( $rout = $rin, undef, undef, 0.0 ) ) != 0 ) {
        if ( $read_avail < 0 ) {
            if ( !$!{ EINTR } ) {
                printError( "Pipe read error: $read_avail $!" ) ;
                }
            }
        elsif ( $read_avail > 0 ) {
            chomp( my $txt = sysreadline( READER ) ) ;
            printDebug( "PARENT GOT RAW TEXT-->$txt" ) ;
            my ( $job, $msg ) = split( "--TYPE--", $txt ) ;

            if ( $job eq "message" ) {
                my ( $id, $tmsg ) = split( "--SPLIT--", $msg ) ;
                printDebug( "GOT JOB==>To: $id, message: $tmsg" ) ;
                foreach ( @active_connections ) {
                    if ( ( $_->{ id } eq $id ) && exists $_->{ conn } ) {
                        my $tip   = $_->{ conn }->ip() ;
                        my $tport = $_->{ conn }->port() ;
                        printInfo( "Sending child message to $tip:$tport..." ) ;
                        eval { $_->{ conn }->send_utf8( $tmsg ) ; } ;
                        if ( $@ ) {

                            printInfo("Marking "
                                    . $_->{ conn }->ip()
                                    . " as bad socket" ) ;
                            $_->{ state } = INVALID_CONNECTION ;

                            }
                        }
                    }

                }

            # Update badge count of active connection
            elsif ( $job eq "badge" ) {
                my ( $id, $badge ) = split( "--SPLIT--", $msg ) ;
                printDebug( "GOT JOB==> Update badge to:"
                        . $badge
                        . " for id:"
                        . $id ) ;
                foreach ( @active_connections ) {
                    if ( $_->{ id } eq $id ) {
                        $_->{ badge } = $badge ;
                        }

                    }

                }

            # hook script result will be updated in ZM DB
            elsif ( $job eq "event_description" ) {
                my ( $mid, $eid, $desc ) = split( "--SPLIT--", $msg ) ;
                printDebug( "GOT JOB==> Update monitor "
                        . $mid
                        . " description:"
                        . $desc ) ;

		printInfo("Force updating event $eid with desc:$desc");
	        updateEventinZmDB( $eid, $desc ) ;
		# Edited Sep 4 2019: Lets write it immediately
		# There are issues with post writing I haven't figured out yet
		# Should not be an issue - we add to front, while new notes go to the end
		#
                # If the hook took too long and the alarm already closed,
                # we need to handle it here. Two situations:
                # a) that mid is now handling a new alarm
                # b) that mid is now idling

		#if (   ( $last_event_for_monitors{ $mid }{ "eid" } != $eid )
		#    || ( $last_event_for_monitors{ $mid }{ "state" } eq "idle" )
		#    ) {
		#    printDebug(
		#        "HOOK: script for eid:$eid returned after the alarm closed, so writing hook text:$desc now..."
		#        ) ;
		#    updateEventinZmDB( $eid, $desc ) ;
		#    $last_event_for_monitors{ $mid }{ "hook_text" } = undef ;
		#    }

            #  hook returned before the alarm closed, so we will catch it in the
            # main loop
	    # else {
	    #        $last_event_for_monitors{ $mid }{ "hook_text" } = $desc ;
	    #        }

	    }

        # marks the latest time an event was sent out. Needed for interval mgmt.
            elsif ( $job eq "timestamp" ) {
                my ( $id, $mid, $timeval ) = split( "--SPLIT--", $msg ) ;
                printDebug( "GOT JOB==> Update last sent timestamp of monitor:"
                        . $mid . " to "
                        . $timeval
                        . " for id:"
                        . $id ) ;
                foreach ( @active_connections ) {
                    if ( $_->{ id } eq $id ) {
                        $_->{ last_sent }->{ $mid } = $timeval ;

                        }

                    }

                #dump(@active_connections);
                }
            else {
                printDebug( "Job message not recognized!" ) ;
                }
            }
        }
    printDebug( "Empty job queue" ) ;
    }

# returns extra fields associated to a connection
sub getConnFields {
    my $conn    = shift ;
    my $matched = "" ;
    foreach ( @active_connections ) {
        if ( exists $_->{ conn } && $_->{ conn } == $conn ) {
            $matched = $_->{ extra_fields } ;
            $matched = ' [' . $matched . '] ' if $matched ;
            last ;

            }
        }
    return $matched ;
    }

# This runs at each tick to purge connections
# that are inactive or have had an error
# This also closes any connection that has not provided
# credentials in the time configured after opening a socket
sub checkConnection {
    foreach ( @active_connections ) {
        my $curtime = time() ;
        if ( $_->{ state } == PENDING_AUTH ) {

            # This takes care of purging connections that have not authenticated
            if ( $curtime - $_->{ time } > $auth_timeout ) {

        # What happens if auth is not provided but device token is registered?
        # It may still be a bogus token, so don't risk keeping connection stored
                if ( exists $_->{ conn } ) {
                    my $conn = $_->{ conn } ;
                    printInfo("Rejecting "
                            . $conn->ip()
                            . getConnFields( $conn )
                            . " - authentication timeout" ) ;
                    $_->{ state } = PENDING_DELETE ;
                    my $str = encode_json( {
                            event  => 'auth',
                            type   => '',
                            status => 'Fail',
                            reason => 'NOAUTH'
                            }
                        ) ;
                    eval { $_->{ conn }->send_utf8( $str ) ; } ;
                    $_->{ conn }->disconnect() ;
                    }
                }
            }

        }
    @active_connections =
        grep { $_->{ state } != PENDING_DELETE } @active_connections ;

    my $ac = scalar @active_connections ;
    my $fcm_conn =
        scalar grep { $_->{ state } == VALID_CONNECTION && $_->{ type } == FCM }
        @active_connections ;
    my $fcm_no_conn =
        scalar
        grep { $_->{ state } == INVALID_CONNECTION && $_->{ type } == FCM }
        @active_connections ;
    my $pend_conn =
        scalar grep { $_->{ state } == PENDING_AUTH } @active_connections ;
    my $mqtt_conn = scalar grep { $_->{ type } == MQTT } @active_connections ;
    my $web_conn =
        scalar grep { $_->{ state } == VALID_CONNECTION && $_->{ type } == WEB }
        @active_connections ;
    my $web_no_conn =
        scalar
        grep { $_->{ state } == INVALID_CONNECTION && $_->{ type } == WEB }
        @active_connections ;

    printDebug(
        "After tick: TOTAL: $ac, FCM+WEB: $fcm_conn, FCM: $fcm_no_conn, WEB: $web_conn, MQTT:$mqtt_conn, invalid WEB: $web_no_conn, PENDING: $pend_conn"
        ) ;

    }

# tokens can have : , so right split - this way I don't break existing token files
# http://stackoverflow.com/a/37870235/1361529
sub rsplit {
    my $pattern = shift( @_ ) ;   # Precompiled regex pattern (i.e. qr/pattern/)
    my $expr    = shift( @_ ) ;   # String to split
    my $limit   = shift( @_ ) ;   # Number of chunks to split into
    map { scalar reverse( $_ ) }
        reverse split( /$pattern/, scalar reverse( $expr ), $limit ) ;
    }

# This function  is called whenever we receive a message from a client
sub processIncomingMessage {
    my ( $conn, $msg ) = @_ ;

    my $json_string ;
    eval { $json_string = decode_json( $msg ) ; } ;
    if ( $@ ) {

        printInfo( "Failed decoding json in processIncomingMessage: $@" ) ;
        my $str = encode_json( {
                event  => 'malformed',
                type   => '',
                status => 'Fail',
                reason => 'BADJSON'
                }
            ) ;
        eval { $conn->send_utf8( $str ) ; } ;
        return ;
        }

    # This event type is when a command related to push notification is received
    if ( ( $json_string->{ 'event' } eq "push" ) && !$use_fcm ) {
        my $str = encode_json( {
                event  => 'push',
                type   => '',
                status => 'Fail',
                reason => 'PUSHDISABLED'
                }
            ) ;
        eval { $conn->send_utf8( $str ) ; } ;
        return ;
        }

#-----------------------------------------------------------------------------------
# "push" event processing
#-----------------------------------------------------------------------------------
    elsif ( ( $json_string->{ 'event' } eq "push" ) && $use_fcm ) {

# sets the unread event count of events for a specific connection
# the server keeps a tab of # of events it pushes out per connection
# but won't know when the client has read them, so the client call tell the server
# using this message
        if ( $json_string->{ 'data' }->{ 'type' } eq "badge" ) {
            foreach ( @active_connections ) {
                if (   ( exists $_->{ conn } )
                    && ( $_->{ conn }->ip() eq $conn->ip() )
                    && ( $_->{ conn }->port() eq $conn->port() ) ) {

                    #print "Badge match, setting to 0\n";
                    $_->{ badge } = $json_string->{ 'data' }->{ 'badge' } ;
                    }
                }
            return ;
            }

        # This sub type is when a device token is registered
        if ( $json_string->{ 'data' }->{ 'type' } eq "token" ) {

            # a token must have a platform
            if ( !$json_string->{ 'data' }->{ 'platform' } ) {
                my $str = encode_json( {
                        event  => 'push',
                        type   => 'token',
                        status => 'Fail',
                        reason => 'MISSINGPLATFORM'
                        }
                    ) ;
                eval { $conn->send_utf8( $str ) ; } ;
                return ;
                }
            foreach ( @active_connections ) {

                # this token already exists so we just update records
                if ( $_->{ token } eq $json_string->{ 'data' }->{ 'token' } ) {

               # if the token doesn't belong to the same connection
               # then we have two connections owning the same token
               # so we need to delete the old one. This can happen when you load
               # the token from the persistent file and there is no connection
               # and then the client is loaded
                    if (
                        ( !exists $_->{ conn } )
                        || (   $_->{ conn }->ip() ne $conn->ip()
                            || $_->{ conn }->port() ne $conn->port() )
                            ) {
                        printDebug( "token matched but connection did not" ) ;
                        printInfo("Duplicate token found: marking ..."
                                . substr( $_->{ token }, -10 )
                                . " to be deleted" ) ;

                        $_->{ state } = PENDING_DELETE ;

                        }
                    else # token matches and connection matches, so it may be an update
                    {
                        printDebug( "token and connection matched" ) ;
                        $_->{ type }  = FCM ;
                        $_->{ token } = $json_string->{ 'data' }->{ 'token' } ;
                        $_->{ platform } =
                            $json_string->{ 'data' }->{ 'platform' } ;
                        if ( exists( $json_string->{ 'data' }->{ 'monlist' } )
                            && ( $json_string->{ 'data' }->{ 'monlist' } ne "" )
                            ) {
                            $_->{ monlist } =
                                $json_string->{ 'data' }->{ 'monlist' } ;
                            }
                        else {
                            $_->{ monlist } = "-1" ;
                            }
                        if ( exists( $json_string->{ 'data' }->{ 'intlist' } )
                            && ( $json_string->{ 'data' }->{ 'intlist' } ne "" )
                            ) {
                            $_->{ intlist } =
                                $json_string->{ 'data' }->{ 'intlist' } ;
                            }
                        else {
                            $_->{ intlist } = "-1" ;
                            }
                        $_->{ pushstate } =
                            $json_string->{ 'data' }->{ 'state' } ;
                        printInfo("Storing token ..."
                                . substr( $_->{ token }, -10 )
                                . ",monlist:"
                                . $_->{ monlist }
                                . ",intlist:"
                                . $_->{ intlist }
                                . ",pushstate:"
                                . $_->{ pushstate }
                                . "\n" ) ;
                        my ( $emonlist, $eintlist ) = saveFCMTokens(
                            $_->{ token },
                            $_->{ monlist },
                            $_->{ intlist },
                            $_->{ platform },
                            $_->{ pushstate }
                            ) ;
                        $_->{ monlist } = $emonlist ;
                        $_->{ intlist } = $eintlist ;
                        }    # token and conn. matches
                    }    # end of token matches
                         # The connection matches but the token does not
                 # this can happen if this is the first token registration after push notification registration
                 # response is received
                if (   ( exists $_->{ conn } )
                    && ( $_->{ conn }->ip() eq $conn->ip() )
                    && ( $_->{ conn }->port() eq $conn->port() )
                    && (
                        $_->{ token } ne $json_string->{ 'data' }->{ 'token' } )
                        ) {
                    printDebug(
                        "connection matched but token did not. first registration?"
                        ) ;
                    $_->{ type }  = FCM ;
                    $_->{ token } = $json_string->{ 'data' }->{ 'token' } ;
                    $_->{ platform } =
                        $json_string->{ 'data' }->{ 'platform' } ;
                    $_->{ monlist } = $json_string->{ 'data' }->{ 'monlist' } ;
                    $_->{ intlist } = $json_string->{ 'data' }->{ 'intlist' } ;
                    if ( exists( $json_string->{ 'data' }->{ 'monlist' } )
                        && ( $json_string->{ 'data' }->{ 'monlist' } ne "" ) ) {
                        $_->{ monlist } =
                            $json_string->{ 'data' }->{ 'monlist' } ;
                        }
                    else {
                        $_->{ monlist } = "-1" ;
                        }
                    if ( exists( $json_string->{ 'data' }->{ 'intlist' } )
                        && ( $json_string->{ 'data' }->{ 'intlist' } ne "" ) ) {
                        $_->{ intlist } =
                            $json_string->{ 'data' }->{ 'intlist' } ;
                        }
                    else {
                        $_->{ intlist } = "-1" ;
                        }
                    $_->{ pushstate } = $json_string->{ 'data' }->{ 'state' } ;
                    printInfo("Storing token ..."
                            . substr( $_->{ token }, -10 )
                            . ",monlist:"
                            . $_->{ monlist }
                            . ",intlist:"
                            . $_->{ intlist }
                            . ",pushstate:"
                            . $_->{ pushstate }
                            . "\n" ) ;
                    my ( $emonlist, $eintlist ) = saveFCMTokens(
                        $_->{ token },
                        $_->{ monlist },
                        $_->{ intlist },
                        $_->{ platform },
                        $_->{ pushstate }
                        ) ;
                    $_->{ monlist } = $emonlist ;
                    $_->{ intlist } = $eintlist ;

                    }
                }

            }

        }    # event = push
     #-----------------------------------------------------------------------------------
     # "control" event processing
     #-----------------------------------------------------------------------------------
    elsif ( ( $json_string->{ 'event' } eq "control" ) ) {
        if ( $json_string->{ 'data' }->{ 'type' } eq "filter" ) {
            if ( !exists( $json_string->{ 'data' }->{ 'monlist' } ) ) {
                my $str = encode_json( {
                        event  => 'control',
                        type   => 'filter',
                        status => 'Fail',
                        reason => 'MISSINGMONITORLIST'
                        }
                    ) ;
                eval { $conn->send_utf8( $str ) ; } ;
                return ;
                }
            if ( !exists( $json_string->{ 'data' }->{ 'intlist' } ) ) {
                my $str = encode_json( {
                        event  => 'control',
                        type   => 'filter',
                        status => 'Fail',
                        reason => 'MISSINGINTERVALLIST'
                        }
                    ) ;
                eval { $conn->send_utf8( $str ) ; } ;
                return ;
                }
            my $monlist = $json_string->{ 'data' }->{ 'monlist' } ;
            my $intlist = $json_string->{ 'data' }->{ 'intlist' } ;
            foreach ( @active_connections ) {
                if (   ( exists $_->{ conn } )
                    && ( $_->{ conn }->ip() eq $conn->ip() )
                    && ( $_->{ conn }->port() eq $conn->port() ) ) {

                    $_->{ monlist } = $monlist ;
                    $_->{ intlist } = $intlist ;
                    printInfo("Contrl: Storing token ..."
                            . substr( $_->{ token }, -10 )
                            . ",monlist:"
                            . $_->{ monlist }
                            . ",intlist:"
                            . $_->{ intlist }
                            . ",pushstate:"
                            . $_->{ pushstate }
                            . "\n" ) ;
                    saveFCMTokens(
                        $_->{ token },
                        $_->{ monlist },
                        $_->{ intlist },
                        $_->{ platform },
                        $_->{ pushstate }
                        ) ;
                    }
                }
            }
        if ( $json_string->{ 'data' }->{ 'type' } eq "version" ) {
            foreach ( @active_connections ) {
                if (   ( exists $_->{ conn } )
                    && ( $_->{ conn }->ip() eq $conn->ip() )
                    && ( $_->{ conn }->port() eq $conn->port() ) ) {
                    my $str = encode_json( {
                            event   => 'control',
                            type    => 'version',
                            status  => 'Success',
                            reason  => '',
                            version => $app_version
                            }
                        ) ;
                    eval { $_->{ conn }->send_utf8( $str ) ; } ;

                    }
                }
            }

        }    # event = control

#-----------------------------------------------------------------------------------
# "auth" event processing
#-----------------------------------------------------------------------------------
# This event type is when a command related to authorization is sent
    elsif ( $json_string->{ 'event' } eq "auth" ) {
        my $uname   = $json_string->{ 'data' }->{ 'user' } ;
        my $pwd     = $json_string->{ 'data' }->{ 'password' } ;
        my $monlist = "" ;
        my $intlist = "" ;
        $monlist = $json_string->{ 'data' }->{ 'monlist' }
            if ( exists( $json_string->{ 'data' }->{ 'monlist' } ) ) ;
        $intlist = $json_string->{ 'data' }->{ 'intlist' }
            if ( exists( $json_string->{ 'data' }->{ 'intlist' } ) ) ;

        foreach ( @active_connections ) {
            if (   ( exists $_->{ conn } )
                && ( $_->{ conn }->ip() eq $conn->ip() )
                && ( $_->{ conn }->port() eq $conn->port() )
                && ( $_->{ state } == PENDING_AUTH ) ) {
                if ( !validateZmAuth( $uname, $pwd ) ) {

                    # bad username or password, so reject and mark for deletion
                    my $str = encode_json( {
                            event  => 'auth',
                            type   => '',
                            status => 'Fail',
                            reason => 'BADAUTH'
                            }
                        ) ;
                    eval { $_->{ conn }->send_utf8( $str ) ; } ;
                    printInfo(
                        "marking for deletion - bad authentication provided by "
                            . $_->{ conn }->ip() ) ;
                    $_->{ state } = PENDING_DELETE ;
                    }
                else {

                    # all good, connection auth was valid
                    $_->{ state }   = VALID_CONNECTION ;
                    $_->{ monlist } = $monlist ;
                    $_->{ intlist } = $intlist ;
                    $_->{ token }   = '' ;
                    my $str = encode_json( {
                            event   => 'auth',
                            type    => '',
                            status  => 'Success',
                            reason  => '',
                            version => $app_version
                            }
                        ) ;
                    eval { $_->{ conn }->send_utf8( $str ) ; } ;
                    printInfo( "Correct authentication provided by "
                            . $_->{ conn }->ip() ) ;

                    }
                }
            }
        }    # event = auth
    else {
        my $str = encode_json( {
                event  => $json_string->{ 'event' },
                type   => '',
                status => 'Fail',
                reason => 'NOTSUPPORTED'
                }
            ) ;
        eval { $_->{ conn }->send_utf8( $str ) ; } ;
        }
    }

# Master loader for predefined connections
# As of now, its FCM tokens and MQTT server
sub loadPredefinedConnections {

    # init FCM tokens
    initFCMTokens() if ( $use_fcm ) ;
    initMQTT()      if ( $use_mqtt ) ;
    }

# MQTT init
# currently just a dummy connection for the sake of consistency

sub initMQTT {
    my $mqtt_connection ;

    printInfo( "Initializing MQTT connection..." ) ;

# Note this does not actually connect to the MQTT server. That happens later during publish
    if ( defined $mqtt_username && defined $mqtt_password ) {
        if ( $mqtt_connection = Net::MQTT::Simple->new( $mqtt_server ) ) {
            # Setting up allow insecure connections
            $ENV{ 'MQTT_SIMPLE_ALLOW_INSECURE_LOGIN' } = 'true' ;
            
            $mqtt_connection->login( $mqtt_username, $mqtt_password ) ;
            printInfo( "Intialized MQTT with auth" ) ;
            }
        }
    else {
        if ( $mqtt_connection = Net::MQTT::Simple->new( $mqtt_server ) ) {
            printInfo( "Intialized MQTT without auth" ) ;
            }
        }

    my $id           = gettimeofday ;
    my $connect_time = time() ;
    push @active_connections,
        {
        type         => MQTT,
        state        => VALID_CONNECTION,
        time         => $connect_time,
        monlist      => "",
        intlist      => "",
        last_sent    => {},
        extra_fields => '',
        mqtt_conn    => $mqtt_connection,
        } ;
    }

# loads FCM tokens from file
sub initFCMTokens {
    printInfo( "Initializing FCM tokens..." ) ;
    if ( !-f $token_file ) {
        open( my $foh, '>', $token_file ) ;
        printInfo( "Creating " . $token_file ) ;
        print $foh "" ;
        close( $foh ) ;
        }

    open( my $fh, '<', $token_file ) ;
    chomp( my @lines = <$fh> ) ;
    close( $fh ) ;
    my @uniquetokens = uniq( @lines ) ;

    open( $fh, '>', $token_file ) ;

    # This makes sure we rewrite the file with
    # unique tokens
    foreach ( @uniquetokens ) {
        next if ( $_ eq "" ) ;
        print $fh "$_\n" ;
        my ( $token, $monlist, $intlist, $platform, $pushstate ) =
            rsplit( qr/:/, $_, 5 ) ;    # split (":",$_);
        my $tod = gettimeofday ;
        push @active_connections,
            {
            type         => FCM,
            id           => $tod,
            token        => $token,
            state        => INVALID_CONNECTION,
            time         => time(),
            badge        => 0,
            monlist      => $monlist,
            intlist      => $intlist,
            last_sent    => {},
            platform     => $platform,
            extra_fields => '',
            pushstate    => $pushstate
            } ;

        }
    close( $fh ) ;
    }

# When a client sends a token id,
# I store it in the file
# It can be sent multiple times, with or without
# monitor list, so I retain the old monitor
# list if its not supplied. In the case of zmNinja
# tokens are sent without monitor list when the registration
# id is received from apple, so we handle that situation

sub saveFCMTokens {
    return if ( !$use_fcm ) ;
    my $stoken = shift ;
    if ( $stoken eq "" ) {
        printDebug( "Not saving, no token. Desktop?" ) ;
        return;
        }
    my $smonlist   = shift ;
    my $sintlist   = shift ;
    my $splatform  = shift ;
    my $spushstate = shift ;
    if ( ( $spushstate eq "" ) && ( $stoken ne "" ) ) {
        $spushstate = "enabled" ;
        printDebug(
            "Overriding token state, setting to enabled as I got a null with a valid token"
            ) ;
        }

    printInfo(
        "SaveTokens called with:monlist=$smonlist, intlist=$sintlist, platform=$splatform, push=$spushstate"
        ) ;

    return if ( $stoken eq "" ) ;
    open( my $fh, '<', $token_file )
        || Fatal( "Cannot open for read " . $token_file ) ;
    chomp( my @lines = <$fh> ) ;
    close( $fh ) ;
    my @uniquetokens = uniq( @lines ) ;
    my $found        = 0 ;
    open( my $fh, '>', $token_file )
        || Fatal( "Cannot open for write " . $token_file ) ;

    foreach ( @uniquetokens ) {
        next if ( $_ eq "" ) ;
        my ( $token, $monlist, $intlist, $platform, $pushstate ) =
            rsplit( qr/:/, $_, 5 ) ;    #split (":",$_);
        if ( $token eq $stoken )    # update token in file with new information
        {
            printInfo(
                "token matched, previously stored monlist is: $monlist" ) ;
            $smonlist   = $monlist   if ( $smonlist eq "-1" ) ;
            $sintlist   = $intlist   if ( $sintlist eq "-1" ) ;
            $spushstate = $pushstate if ( $spushstate eq "" ) ;
            printInfo("updating ..."
                    . substr( $token, -10 )
                    . " with push:$pushstate & monlist:$monlist" ) ;
            print $fh "$stoken:$smonlist:$sintlist:$splatform:$spushstate\n" ;
            $found = 1 ;
            }
        else    # write token as is
        {
            if ( $pushstate eq "" ) {
                $pushstate = "enabled" ;
                printDebug( "nochange, but pushstate was EMPTY. WHY?" ) ;
                }
            printDebug( "no change - saving token with $pushstate" ) ;
            print $fh "$token:$monlist:$intlist:$platform:$pushstate\n" ;
            }

        }

    $smonlist = "" if ( $smonlist eq "-1" ) ;
    $sintlist = "" if ( $sintlist eq "-1" ) ;

    if ( !$found ) {
        printInfo(
            "token not found, creating new record with monlist=$smonlist" ) ;
        print $fh "$stoken:$smonlist:$sintlist:$splatform:$spushstate\n" ;
        }
    close( $fh ) ;

    return ( $smonlist, $sintlist ) ;

    }

# This keeps the latest of any duplicate tokens
# we need to ignore monitor list when we do this
sub uniq {
    my %seen ;
    my @array  = reverse @_ ;    # we want the latest
    my @farray = () ;
    foreach ( @array ) {
        next
            if ( $_ =~ /^\s*$/ )
            ; # skip blank lines - we don't really need this - as token check is later
        my ( $token, $monlist, $intlist, $platform, $pushstate ) =
            rsplit( qr/:/, $_, 5 ) ;    #split (":",$_);
        next if ( $token eq "" ) ;
        if ( ( $pushstate ne "enabled" ) && ( $pushstate ne "disabled" ) ) {
            printDebug(
                "huh? uniq read $token,$monlist,$intlist,$platform, $pushstate => forcing state to enabled"
                ) ;
            $pushstate = "enabled" ;

            }

        # not interested in monlist & intlist
        if ( !$seen{ $token }++ ) {
            push @farray, "$token:$monlist:$intlist:$platform:$pushstate" ;
            }

        }
    return @farray ;

    }

# Checks if the monitor for which
# an alarm occurred is part of the monitor list
# for that connection
sub getInterval {
    my $intlist = shift ;
    my $monlist = shift ;
    my $mid     = shift ;

    #print ("getInterval:MID:$mid INT:$intlist AND MON:$monlist\n");
    my @ints = split( ',', $intlist ) ;
    my @mids = split( ',', $monlist ) ;
    my $idx  = -1 ;
    foreach ( @mids ) {
        $idx++ ;

        #print ("Comparing $mid with $_\n");
        if ( $mid eq $_ ) {
            last ;
            }
        }

    #print ("RETURNING index:$idx with Value:".$ints[$idx]."\n");
    return $ints[ $idx ] ;

    }

# Checks if the monitor for which
# an alarm occurred is part of the monitor list
# for that connection
sub isInList {
    my $monlist = shift ;
    my $mid     = shift ;

    my @mids = split( ',', $monlist ) ;
    my $found = 0 ;
    foreach ( @mids ) {
        if ( $mid eq $_ ) {
            $found = 1 ;
            last ;
            }
        }
    return $found ;

    }

# Returns an identity string for a connection for display purposes
sub getConnectionIdentity {
    my $obj = shift ;

    my $identity = "" ;

    if ( $obj->{ type } == FCM ) {
        if ( exists $obj->{ conn } && $obj->{ state } != INVALID_CONNECTION ) {
            $identity =
                $obj->{ conn }->ip() . ":" . $obj->{ conn }->port() . ", " ;
            }
        $identity =
            $identity . "token ending in:..." . substr( $obj->{ token }, -10 ) ;
        }
    elsif ( $obj->{ type } == WEB ) {
        if ( exists $obj->{ conn } ) {
            $identity = $obj->{ conn }->ip() . ":" . $obj->{ conn }->port() ;
            }
        else {
            $identity = "(unknown state?)" ;
            }
        }
    elsif ( $obj->{ type } == MQTT ) {
        $identity = "MQTT " . $mqtt_server ;
        }
    else {
        $identity = "unknown type(!)" ;
        }

    return $identity ;
    }

# Master event send routine. Will invoke different transport APIs as needed based on connection details
sub sendEvent {
    my $alarm = shift ;
    my $ac    = shift ;
    my $t     = gettimeofday ;
    my $str   = encode_json( {
            event  => 'alarm',
            type   => '',
            status => 'Success',
            events => [ $alarm ]
            }
        ) ;

    if (   $ac->{ type } == FCM
        && $ac->{ pushstate } ne "disabled"
        && $ac->{ state } != PENDING_AUTH ) {
        printInfo( "Sending notification over FCM" ) ;
        sendOverFCM( $alarm, $ac ) ;
        }
    elsif ($ac->{ type } == WEB
        && $ac->{ state } == VALID_CONNECTION
        && exists $ac->{ conn } ) {
        sendOverWebSocket( $alarm, $ac ) ;
        }
    elsif ( $ac->{ type } == MQTT ) {
        printInfo( "Sending notification over MQTT" ) ;
        sendOverMQTTBroker( $alarm, $ac ) ;
        }

    print WRITER "timestamp--TYPE--"
        . $ac->{ id }
        . "--SPLIT--"
        . $alarm->{ MonitorId }
        . "--SPLIT--"
        . $t
        . "\n" ;

    }

# Compares connection rules (monList/interval). Returns 1 if event should be send to this connection,
# 0 if not.
sub shouldSendEventToConn {
    my $alarm  = shift ;
    my $ac     = shift ;
    my $retVal = 0 ;

    # Let's see if this connection is interested in this alarm
    my $monlist   = $ac->{ monlist } ;
    my $intlist   = $ac->{ intlist } ;
    my $last_sent = $ac->{ last_sent } ;

    my $id     = getConnectionIdentity( $ac ) ;
    my $connId = $ac->{ id } ;
    printInfo( "Checking alarm rules for $id" ) ;

    if ( $monlist eq "" || isInList( $monlist, $alarm->{ MonitorId } ) ) {
        my $mint = getInterval( $intlist, $monlist, $alarm->{ MonitorId } ) ;
        my $elapsed ;
        my $t = time() ;
        if ( $last_sent->{ $alarm->{ MonitorId } } ) {
            $elapsed = time() - $last_sent->{ $alarm->{ MonitorId } } ;
            if ( $elapsed >= $mint ) {
                printInfo("Monitor "
                        . $alarm->{ MonitorId }
                        . " event: should send out as  $elapsed is >= interval of $mint"
                        ) ;
                $retVal = 1 ;

                }
            else {

                printInfo("Monitor "
                        . $alarm->{ MonitorId }
                        . " event: should NOT send this out as $elapsed is less than interval of $mint"
                        ) ;
                $retVal = 0 ;
                }

            }
        else {
            # This means we have no record of sending any event to this monitor
            #$last_sent->{$_->{MonitorId}} = time();
            printInfo("Monitor "
                    . $alarm->{ MonitorId }
                    . " event: last time not found, so should send" ) ;
            $retVal = 1 ;
            }
        }
    else    # monitorId not in list
    {
        printInfo("should NOT send alarm as Monitor "
                . $alarm->{ MonitorId }
                . " is excluded" ) ;
        $retVal = 0 ;
        }

    return $retVal ;
    }

# If there are events reported in checkNewEvents, processAlarms is called to
# 1. Apply hooks if applicable
# 2. Send them out
# IMPORTANT: processAlarms is called as a forked child
# so remember not to manipulate data owned by the parent that needs to persist
# Use the parent<-child pipe if needed

#  @events will have the list of alarms we need to process and send out
# structure {Name => $name, MonitorId => $mid, EventId => $last_event, Cause=> $alarm_cause};

sub processAlarms {

    # iterate through each alarm
    foreach ( @events ) {
        my $alarm = $_ ;
        printInfo("processAlarms: EID:"
                . $alarm->{ EventId }
                . " Monitor:"
                . $alarm->{ Name }
                . " (id):"
                . $alarm->{ MonitorId }
                . " cause:"
                . $alarm->{ Cause } ) ;

# if you want to use hook, lets first call the hook
# if the hook returns an exit value of 0 (yes/success), we process it, else we skip it

        if ( $hook ) {
            if ( $skip_monitors
                && isInList( $skip_monitors, $alarm->{ MonitorId } ) ) {
                printInfo("Skipping hook processing because "
                        . $alarm->{ Name } . "("
                        . $alarm->{ MonitorId }
                        . ") is in skip monitor list" ) ;
                }
            else {
                my $cmd =
                      $hook . " "
                    . $alarm->{ EventId } . " "
                    . $alarm->{ MonitorId } . " \""
                    . $alarm->{ Name } . "\"" . " \""
                    . $alarm->{ Cause }
                    . "\"" ;

# new ZM 1.33 feature - lets me extract event path so I can store the hook detection image
                if ( $hook_pass_image_path ) {
                    if ( !try_use( "ZoneMinder::Event" ) ) {
                        Error(
                            "ZoneMinder::Event missing, you may be using an old version"
                            ) ;
                        }
                    else {
                        my $event =
                            new ZoneMinder::Event( $alarm->{ EventId } ) ;
                        $cmd = $cmd . " \"" . $event->Path() . "\"" ;
                        printInfo("Adding event path:"
                                . $event->Path()
                                . " to hook for image storage" ) ;
                        }

                    }
                printInfo( "Invoking hook:" . $cmd ) ;
                my $resTxt  = `$cmd` ;
                my $resCode = $? >> 8 ;
                chomp( $resTxt ) ;
                printInfo("For Monitor:"
                        . $alarm->{ MonitorId }
                        . " event:"
                        . $alarm->{ EventId }
                        . ", hook script returned with text:"
                        . $resTxt
                        . " exit:"
                        . $resCode ) ;
                next if ( $resCode != 0 ) ;
                if ( $use_hook_description ) {

       # lets append it to any existing motion notes
       # note that this is in the fork. We are only passing hook text
       # to parent, so it can be appended to the full motion text on event close
                    $alarm->{ Cause } = $resTxt . " " . $alarm->{ Cause } ;
                    printDebug(
                        "after appending motion text, alarm->cause is now:"
                            . $alarm->{ Cause } ) ;

  # This updates the ZM DB with the detected description
  # we are writing resTxt not alarm cause which is only detection text
  # when we write to DB, we will add the latest notes, which may have more zones
                    print WRITER "event_description--TYPE--"
                        . $alarm->{ MonitorId }
                        . "--SPLIT--"
                        . $alarm->{ EventId }
                        . "--SPLIT--"
                        . $resTxt
                        . "\n" ;
                    }
                }
            }

# coming here means the alarm needs to be sent out to listerens who are interested
        printInfo( "Matching alarm to connection rules..." ) ;
        my ( $serv ) = @_ ;
        foreach ( @active_connections ) {

            if ( shouldSendEventToConn( $alarm, $_ ) ) {
                printDebug(
                    "shouldSendEventToConn returned true, so calling sendEvent"
                    ) ;
                sendEvent( $alarm, $_ ) ;

                }
            }    # foreach active_connections

        }    # foreach events

    }

# This is really the main module
# It opens a WSS socket and keeps listening
sub initSocketServer {
    checkNewEvents() ;
    my $ssl_server ;
    if ( $ssl_enabled ) {
        printInfo( "About to start listening to socket" ) ;
        eval {
            $ssl_server = IO::Socket::SSL->new(
                Listen        => 10,
                LocalPort     => $port,
                LocalAddr     => $address,
                Proto         => 'tcp',
                Reuse         => 1,
                ReuseAddr     => 1,
                SSL_cert_file => $ssl_cert_file,
                SSL_key_file  => $ssl_key_file
                ) ;
                } ;
        if ( $@ ) {
            printError( "Failed starting server: $@" ) ;
            exit( -1 ) ;
            }
        printInfo( "Secure WS(WSS) is enabled..." ) ;
        }
    else {
        printInfo( "Secure WS is disabled..." ) ;
        }
    printInfo( "Web Socket Event Server listening on port " . $port . "\n" ) ;

    $wss = Net::WebSocket::Server->new(
        listen => $ssl_enabled ? $ssl_server : $port,
        tick_period => $event_check_interval,
        on_tick     => sub {
            printDebug( "---------->Tick START<--------------" ) ;
            checkConnection() ;
            processJobs() ;
            if ( checkNewEvents() ) {
                my $pid = fork ;
                if ( !defined $pid ) {
                    die "Cannot fork: $!" ;
                    }
                elsif ( $pid == 0 ) {

                    # client
                    local $SIG{ 'CHLD' } = 'DEFAULT' ;
                    my $numAlarms = scalar @events ;
                    printInfo(
                        "Forking process:$$ to handle $numAlarms alarms" ) ;

# send it the list of current events to handle bcause checkNewEvents() will clean it
                    processAlarms( @events ) ;
                    printInfo( "Ending process:$$ to handle alarms" ) ;
                    exit 0 ;
                    }
                }
            printDebug( "---------->Tick END<--------------" ) ;
        },

        # called when a new connection comes in
        on_connect => sub {
            my ( $serv, $conn ) = @_ ;
            printDebug( "---------->onConnect START<--------------" ) ;
            my ( $len ) = scalar @active_connections ;
            printInfo("got a websocket connection from "
                    . $conn->ip() . " ("
                    . $len
                    . ") active connections" ) ;

            #print Dumper($conn);
            $conn->on(
                utf8 => sub {
                    printDebug(
                        "---------->onConnect msg START<--------------" ) ;
                    my ( $conn, $msg ) = @_ ;
                    printDebug( "Raw incoming message: $msg" ) ;
                    processIncomingMessage( $conn, $msg ) ;
                    printDebug(
                        "---------->onConnect msg STOP<--------------" ) ;
                },
                handshake => sub {
                    my ( $conn, $handshake ) = @_ ;
                    printDebug(
                        "---------->onConnect:handshake START<--------------"
                        ) ;
                    my $fields = "" ;

                    # Stuff in more headers you want here over time
                    if ( $handshake->req->fields ) {
                        my $f = $handshake->req->fields ;

                        #print Dumper($f);
                        $fields =
                              $fields
                            . " X-Forwarded-For:"
                            . $f->{ "x-forwarded-for" }
                            if $f->{ "x-forwarded-for" } ;

                       #$fields = $fields." host:".$f->{"host"} if $f->{"host"};

                        }

                    #print Dumper($handshake);
                    my $id           = gettimeofday ;
                    my $connect_time = time() ;
                    push @active_connections,
                        {
                        type         => WEB,
                        conn         => $conn,
                        id           => $id,
                        state        => PENDING_AUTH,
                        time         => $connect_time,
                        monlist      => "",
                        intlist      => "",
                        last_sent    => {},
                        platform     => "websocket",
                        pushstate    => '',
                        extra_fields => $fields,
                        badge        => 0
                        } ;
                    printInfo(
                        "Websockets: New Connection Handshake requested from "
                            . $conn->ip() . ":"
                            . $conn->port()
                            . getConnFields( $conn )
                            . " state=pending auth, id="
                            . $id ) ;

                    printDebug(
                        "---------->onConnect:handshake END<--------------" ) ;
                },
                disconnect => sub {
                    my ( $conn, $code, $reason ) = @_ ;
                    printDebug(
                        "---------->onConnect:disconnect START<--------------"
                        ) ;
                    printInfo("Websocket remotely disconnected from "
                            . $conn->ip()
                            . getConnFields( $conn ) ) ;
                    foreach ( @active_connections ) {
                        if (   ( exists $_->{ conn } )
                            && ( $_->{ conn }->ip() eq $conn->ip() )
                            && ( $_->{ conn }->port() eq $conn->port() ) ) {

                            # mark this for deletion only if device token
                            # not present
                            if ( $_->{ token } eq '' ) {
                                $_->{ state } = PENDING_DELETE ;
                                printInfo("Marking "
                                        . $conn->ip()
                                        . getConnFields( $conn )
                                        . " for deletion as websocket closed remotely\n"
                                        ) ;
                                }
                            else {

                                printInfo(
                                    "Invaliding websocket, but NOT Marking "
                                        . $conn->ip()
                                        . getConnFields( $conn )
                                        . " for deletion as token "
                                        . $_->{ token }
                                        . " active\n" ) ;
                                $_->{ state } = INVALID_CONNECTION ;
                                }
                            }

                        }
                    printDebug(
                        "---------->onConnect:disconnect END<--------------" ) ;
                },
                ) ;

            printDebug( "---------->onConnect STOP<--------------" ) ;
            }
            )->start ;
    }
