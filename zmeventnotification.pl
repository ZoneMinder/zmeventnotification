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
use POSIX ':sys_wait_h';
use Time::HiRes qw/gettimeofday/;
use Symbol qw(qualify_to_ref);
use IO::Select;

if ( !try_use('JSON') ) {
  if ( !try_use('JSON::XS') ) {
    Fatal('JSON or JSON::XS  missing');
    exit(-1);
  }
}

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

my $app_version = '5.15';

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
  DEFAULT_CONFIG_FILE        => '/etc/zm/zmeventnotification.ini',
  DEFAULT_PORT               => 9000,
  DEFAULT_ADDRESS            => '[::]',
  DEFAULT_AUTH_ENABLE        => 'yes',
  DEFAULT_AUTH_TIMEOUT       => 20,
  DEFAULT_FCM_ENABLE         => 'yes',
  DEFAULT_MQTT_ENABLE        => 'no',
  DEFAULT_MQTT_SERVER        => '127.0.0.1',
  DEFAULT_MQTT_TOPIC         => 'zoneminder',
  DEFAULT_MQTT_TICK_INTERVAL => 15,
  DEFAULT_MQTT_RETAIN        => 'no',
  DEFAULT_FCM_TOKEN_FILE     => '/var/lib/zmeventnotification/push/tokens.txt',

  DEFAULT_USE_API_PUSH => 'no',

  DEFAULT_BASE_DATA_PATH                    => '/var/lib/zmeventnotification',
  DEFAULT_SSL_ENABLE                        => 'yes',
  DEFAULT_CUSTOMIZE_VERBOSE                 => 'no',
  DEFAULT_CUSTOMIZE_EVENT_CHECK_INTERVAL    => 5,
  DEFAULT_CUSTOMIZE_ES_DEBUG_LEVEL          => 2,
  DEFAULT_CUSTOMIZE_MONITOR_RELOAD_INTERVAL => 300,
  DEFAULT_CUSTOMIZE_READ_ALARM_CAUSE        => 'no',
  DEFAULT_CUSTOMIZE_TAG_ALARM_EVENT_ID      => 'no',
  DEFAULT_CUSTOMIZE_USE_CUSTOM_NOTIFICATION_SOUND => 'no',
  DEFAULT_CUSTOMIZE_INCLUDE_PICTURE               => 'no',

  DEFAULT_USE_HOOKS                          => 'no',
  DEFAULT_HOOK_KEEP_FRAME_MATCH_TYPE         => 'yes',
  DEFAULT_HOOK_USE_HOOK_DESCRIPTION          => 'no',
  DEFAULT_HOOK_STORE_FRAME_IN_ZM             => 'no',
  DEFAULT_RESTART_INTERVAL                   => 7200,
  DEFAULT_EVENT_START_NOTIFY_ON_HOOK_FAIL    => 'none',
  DEFAULT_EVENT_START_NOTIFY_ON_HOOK_SUCCESS => 'none',
  DEFAULT_EVENT_END_NOTIFY_ON_HOOK_FAIL      => 'none',
  DEFAULT_EVENT_END_NOTIFY_ON_HOOK_SUCCESS   => 'none',
  DEFAULT_EVENT_END_NOTIFY_IF_START_SUCCESS  => 'yes',
  DEFAULT_SEND_EVENT_END_NOTIFICATION        => 'no',
  DEFAULT_USE_ESCONTROL_INTERFACE            => 'no',
  DEFAULT_ESCONTROL_INTERFACE_FILE =>
    '/var/lib/zmeventnotification/misc/escontrol_interface.dat',
  DEFAULT_FCM_DATE_FORMAT => '%I:%M %p, %d-%b'
};

# connection state
use constant {
  PENDING_AUTH       => 1,
  VALID_CONNECTION   => 2,
  INVALID_CONNECTION => 3,
  PENDING_DELETE     => 4,
};

# connection types
use constant {
  FCM  => 1000,
  MQTT => 1001,
  WEB  => 1002
};

# child fork states
use constant {
  ACTIVE => 100,
  EXITED => 101
};

# escontrol notification states
use constant {
  ESCONTROL_FORCE_NOTIFY   => 1,
  ESCONTROL_DEFAULT_NOTIFY => 0,
  ESCONTROL_FORCE_MUTE     => -1,

};

my $child_forks = 0;    # Global tracker of active children

# Declare options.

my $help;
my $version;

my $config_file;
my $config_file_present;
my $check_config;

my $use_escontrol_interface;
my $escontrol_interface_password;
my $escontrol_interface_file;

my $port;
my $address;

my $auth_enabled;
my $auth_timeout;

my $use_mqtt;
my $mqtt_server;
my $mqtt_topic;
my $mqtt_username;
my $mqtt_password;
my $mqtt_tick_interval;
my $mqtt_retain;
my $mqtt_last_tick_time = time();

my $use_fcm;
my $fcm_api_key;

my $use_api_push;
my $api_push_script;

my $token_file;
my $fcm_date_format;

my $ssl_enabled;
my $ssl_cert_file;
my $ssl_key_file;

my $console_logs;
my $es_debug_level;
my $event_check_interval;
my $monitor_reload_interval;
my $read_alarm_cause;
my $tag_alarm_event_id;
my $use_custom_notification_sound;
my $send_event_end_notification;

my $use_hooks;
my $event_start_hook;
my $event_end_hook;
my $event_start_hook_notify_userscript;
my $event_end_hook_notify_userscript;

my $event_start_notify_on_hook_fail;
my $event_start_notify_on_hook_success;
my %event_start_notify_on_hook_fail;
my %event_start_notify_on_hook_success;

my $event_end_notify_on_hook_fail;
my $event_end_notify_on_hook_success;
my %event_end_notify_on_hook_fail;
my %event_end_notify_on_hook_success;

my $event_end_notify_if_start_success;

my $use_hook_description;
my $keep_frame_match_type;
my $skip_monitors;
my %skip_monitors;
my $hook_skip_monitors;
my %hook_skip_monitors;
my $hook_pass_image_path;

my $picture_url;
my $include_picture;
my $picture_portal_username;
my $picture_portal_password;

my $secrets;
my $secrets_filename;
my $base_data_path;

my $restart_interval;

my $prefix = "PARENT:";

# admin interface options

my %escontrol_interface_settings = ( notifications => {} );

#default key. Please don't change this
use constant NINJA_API_KEY =>
  'AAAApYcZ0mA:APA91bG71SfBuYIaWHJorjmBQB3cAN7OMT7bAxKuV3ByJ4JiIGumG6cQw0Bo6_fHGaWoo4Bl-SlCdxbivTv5Z-2XPf0m86wsebNIG15pyUHojzmRvJKySNwfAHs7sprTGsA_SIR_H43h';

my $dummyEventTest = 0
  ; # if on, will generate dummy events. Not in config for a reason. Only dev testing
my $dummyEventInterval     = 20;       # timespan to generate events in seconds
my $dummyEventTimeLastSent = time();

# This part makes sure we have the right core deps. See later for optional deps

if ( !try_use('Net::WebSocket::Server') ) {
  Fatal('Net::WebSocket::Server missing');
}
if ( !try_use('IO::Socket::SSL') )  { Fatal('IO::Socket::SSL missing'); }
if ( !try_use('IO::Handle') )       { Fatal('IO::Handle'); }
if ( !try_use('Config::IniFiles') ) { Fatal('Config::Inifiles missing'); }
if ( !try_use('Getopt::Long') )     { Fatal('Getopt::Long missing'); }
if ( !try_use('File::Basename') )   { Fatal('File::Basename missing'); }
if ( !try_use('File::Spec') )       { Fatal('File::Spec missing'); }
if ( !try_use('URI::Escape') )      { Fatal('URI::Escape missing'); }
if ( !try_use('Storable') )         { Fatal('Storable missing'); }

#if (!try_use ("threads")) {Fatal ("threads library/support  missing");}

use constant USAGE => <<'USAGE';

Usage: zmeventnotification.pl [OPTION]...

  --help                              Print this page.
  --version                           Print version.
  --config=FILE                       Read options from configuration file (default: /etc/zm/zmeventnotification.ini).
                                      Any CLI options used below will override config settings.

  --check-config                      Print configuration and exit.

USAGE

GetOptions(
  'help'         => \$help,
  'version'      => \$version,
  'config=s'     => \$config_file,
  'check-config' => \$check_config,
);

if ($version) {
  print($app_version);
  exit(0);
}
exit( print(USAGE) ) if $help;

# Read options from a configuration file.  If --config is specified, try to
# read it and fail if it can't be read.  Otherwise, try the default
# configuration path, and if it doesn't exist, take all the default values by
# loading a blank Config::IniFiles object.

if ( !$config_file ) {
  $config_file         = DEFAULT_CONFIG_FILE;
  $config_file_present = -e $config_file;
}
else {
  if ( !-e $config_file ) {
    Fatal("$config_file does not exist!");
  }
  $config_file_present = 1;
}

my $config;

if ($config_file_present) {
  printInfo("using config file: $config_file");
  $config = Config::IniFiles->new( -file => $config_file );

  unless ($config) {
    Fatal( "Encountered errors while reading $config_file:\n"
        . join( "\n", @Config::IniFiles::errors ) );
  }
}
else {
  $config = Config::IniFiles->new;
  printInfo('No config file found, using inbuilt defaults');
}

$secrets_filename = config_get_val( $config, 'general', 'secrets' );
if ($secrets_filename) {
  printInfo("using secrets file: $secrets_filename");
  $secrets = Config::IniFiles->new( -file => $secrets_filename );
  unless ($secrets) {
    Fatal( "Encountered errors while reading $secrets_filename:\n"
        . join( "\n", @Config::IniFiles::errors ) );
  }
}

$escontrol_interface_file =
  config_get_val( $config, 'general', "escontrol_interface_file",
  DEFAULT_ESCONTROL_INTERFACE_FILE );

$use_escontrol_interface =
  config_get_val( $config, 'general', 'use_escontrol_interface',
  DEFAULT_USE_ESCONTROL_INTERFACE );
$escontrol_interface_password =
  config_get_val( $config, 'general', 'escontrol_interface_password' )
  if ($use_escontrol_interface);

# secrets need to be loaded before admin
# Do this BEFORE any config_get_val
loadEsControlSettings();

# This will not load parameters in the .ini files
loadEsConfigSettings();

my %ssl_push_opts = ();

if ( $ssl_enabled && ( !$ssl_cert_file || !$ssl_key_file ) ) {
  Fatal('SSL is enabled, but key or certificate file is missing');
}

my $notId = 1;

if ($hook_pass_image_path) {
  if ( !try_use('ZoneMinder::Event') ) {
    Fatal(
      'ZoneMinder::Event missing, you may be using an old version. Please turn off hook_pass_image_path in yoyr config'
    );
  }
}

# this is just a wrapper around Config::IniFiles val
# older versions don't support a default parameter
sub config_get_val {
  my ( $config, $sect, $parm, $def ) = @_;
  my $val = $config->val( $sect, $parm );

  my $final_val = defined($val) ? $val : $def;

  my $fc = substr( $final_val, 0, 1 );

  #printInfo ("Parsing $final_val with X${fc}X");
  if ( $fc eq '!' ) {
    my $token = substr( $final_val, 1 );
    printDebug( 'Got secret token !' . $token,2 );
    Fatal('No secret file found') if ( !$secrets );
    my $secret_val = $secrets->val( 'secrets', $token );
    Fatal( 'Token:' . $token . ' not found in secret file' )
      if ( !$secret_val );

    #printInfo ('replacing with:'.$secret_val);
    $final_val = $secret_val;
  }

  #printInfo("ESCONTROL_INTERFACE checking override for $parm");
  if ( exists $escontrol_interface_settings{$parm} ) {
    printDebug( "ESCONTROL_INTERFACE overrides key: $parm with "
        . $escontrol_interface_settings{$parm},2 );
    $final_val = $escontrol_interface_settings{$parm};
  }

  # compatibility hack, lets use yes/no in config to maintain
  # parity with hook config
  if    ( lc($final_val) eq 'yes' ) { $final_val = 1; }
  elsif ( lc($final_val) eq 'no' )  { $final_val = 0; }

  # now search for substitutions
  my @matches = ( $final_val =~ /\{\{(.*?)\}\}/g );

  foreach (@matches) {

    my $token = $_;

    # check if token exists in either general or its own section
    # other-section substitution not supported

    my $val = $config->val( 'general', $token );
    $val = $config->val( $sect, $token ) if !$val;
    printDebug("config string substitution: {{$token}} is '$val'",3);
    $final_val =~ s/\{\{$token\}\}/$val/g;

  }

  return $final_val;
}

# Loads all the ini file settings and populates variables
sub loadEsConfigSettings {
  $restart_interval = config_get_val( $config, 'general', 'restart_interval',
    DEFAULT_RESTART_INTERVAL );
  if ( !$restart_interval ) {
    printDebug('ES will not be restarted as interval is specified as 0',1);
  }
  else {
    printDebug("ES will be restarted at $restart_interval seconds",1);
  }
  $skip_monitors = config_get_val( $config, 'general', 'skip_monitors' );
  %skip_monitors = map { $_ => !undef } split( ',', $skip_monitors );

  # If an option set a value, leave it.  If there's a value in the config, use
  # it.  Otherwise, use a default value if it's available.

  $base_data_path = config_get_val( $config, 'general', 'base_data_path',
    DEFAULT_BASE_DATA_PATH );

  $port    = config_get_val( $config, 'network', 'port',    DEFAULT_PORT );
  $address = config_get_val( $config, 'network', 'address', DEFAULT_ADDRESS );
  $auth_enabled =
    config_get_val( $config, 'auth', 'enable', DEFAULT_AUTH_ENABLE );
  $auth_timeout =
    config_get_val( $config, 'auth', 'timeout', DEFAULT_AUTH_TIMEOUT );
  $use_mqtt = config_get_val( $config, 'mqtt', 'enable', DEFAULT_MQTT_ENABLE );
  $mqtt_server =
    config_get_val( $config, 'mqtt', 'server', DEFAULT_MQTT_SERVER );
  $mqtt_topic =
    config_get_val( $config, 'mqtt', 'topic', DEFAULT_MQTT_TOPIC );
  $mqtt_username = config_get_val( $config, 'mqtt', 'username' );
  $mqtt_password = config_get_val( $config, 'mqtt', 'password' );
  $mqtt_tick_interval =
    config_get_val( $config, 'mqtt', 'tick_interval',
    DEFAULT_MQTT_TICK_INTERVAL );
  $mqtt_retain =
    config_get_val( $config, 'mqtt', 'retain', DEFAULT_MQTT_RETAIN );

  $use_fcm = config_get_val( $config, 'fcm', 'enable', DEFAULT_FCM_ENABLE );
  $fcm_api_key = config_get_val( $config, 'fcm', 'api_key', NINJA_API_KEY );
  $fcm_date_format =
    config_get_val( $config, 'fcm', 'date_format', DEFAULT_FCM_DATE_FORMAT );

  $use_api_push =
    config_get_val( $config, 'push', 'use_api_push', DEFAULT_USE_API_PUSH );
  if ($use_api_push) {
    $api_push_script = config_get_val( $config, 'push', 'api_push_script' );
    Error("You have API push enabled, but no script to handle API pushes")
      if ( !$api_push_script );

  }

  $token_file =
    config_get_val( $config, 'fcm', 'token_file', DEFAULT_FCM_TOKEN_FILE );
  $ssl_enabled = config_get_val( $config, 'ssl', 'enable', DEFAULT_SSL_ENABLE );
  $ssl_cert_file = config_get_val( $config, 'ssl', 'cert' );
  $ssl_key_file  = config_get_val( $config, 'ssl', 'key' );
  $console_logs = config_get_val( $config, 'customize', 'console_logs',
    DEFAULT_CUSTOMIZE_VERBOSE );
  $es_debug_level = config_get_val( $config, 'customize', 'es_debug_level',
    DEFAULT_CUSTOMIZE_ES_DEBUG_LEVEL );
  $event_check_interval =
    config_get_val( $config, 'customize', 'event_check_interval',
    DEFAULT_CUSTOMIZE_EVENT_CHECK_INTERVAL );
  $monitor_reload_interval =
    config_get_val( $config, 'customize', 'monitor_reload_interval',
    DEFAULT_CUSTOMIZE_MONITOR_RELOAD_INTERVAL );
  $read_alarm_cause =
    config_get_val( $config, 'customize', 'read_alarm_cause',
    DEFAULT_CUSTOMIZE_READ_ALARM_CAUSE );
  $tag_alarm_event_id =
    config_get_val( $config, 'customize', 'tag_alarm_event_id',
    DEFAULT_CUSTOMIZE_TAG_ALARM_EVENT_ID );
  $use_custom_notification_sound = config_get_val(
    $config, 'customize',
    'use_custom_notification_sound',
    DEFAULT_CUSTOMIZE_USE_CUSTOM_NOTIFICATION_SOUND
  );
  $picture_url = config_get_val( $config, 'customize', 'picture_url' );
  $include_picture = config_get_val( $config, 'customize', 'include_picture',
    DEFAULT_CUSTOMIZE_INCLUDE_PICTURE );
  $picture_portal_username =
    config_get_val( $config, 'customize', 'picture_portal_username' );
  $picture_portal_password =
    config_get_val( $config, 'customize', 'picture_portal_password' );

  $send_event_end_notification =
    config_get_val( $config, 'customize', 'send_event_end_notification',
    DEFAULT_SEND_EVENT_END_NOTIFICATION );

  $use_hooks =
    config_get_val( $config, 'customize', 'use_hooks', DEFAULT_USE_HOOKS );

  $event_start_hook = config_get_val( $config, 'hook', 'event_start_hook' );
  $event_start_hook_notify_userscript = config_get_val( $config, 'hook', 'event_start_hook_notify_userscript' );
  $event_end_hook_notify_userscript = config_get_val( $config, 'hook', 'event_end_hook_notify_userscript' );

  # backward compatibility
  $event_start_hook = config_get_val( $config, 'hook', 'hook_script' )
    if ( !$event_start_hook );
  $event_end_hook = config_get_val( $config, 'hook', 'event_end_hook' );

  $event_start_notify_on_hook_fail = config_get_val(
    $config, 'hook',
    'event_start_notify_on_hook_fail',
    DEFAULT_EVENT_START_NOTIFY_ON_HOOK_FAIL
  );
  $event_start_notify_on_hook_success = config_get_val(
    $config, 'hook',
    'event_start_notify_on_hook_success',
    DEFAULT_EVENT_START_NOTIFY_ON_HOOK_SUCCESS
  );

  $event_end_notify_on_hook_fail = config_get_val(
    $config, 'hook',
    'event_end_notify_on_hook_fail',
    DEFAULT_EVENT_END_NOTIFY_ON_HOOK_FAIL
  );
  $event_end_notify_on_hook_success = config_get_val(
    $config, 'hook',
    'event_end_notify_on_hook_success',
    DEFAULT_EVENT_END_NOTIFY_ON_HOOK_SUCCESS
  );

  # get channels and convert to hash

  %event_start_notify_on_hook_fail = map { $_ => 1 }
    split( /\s*,\s*/, lc($event_start_notify_on_hook_fail) );
  %event_start_notify_on_hook_success = map { $_ => 1 }
    split( /\s*,\s*/, lc($event_start_notify_on_hook_success) );
  %event_end_notify_on_hook_fail =
    map { $_ => 1 } split( /\s*,\s*/, lc($event_end_notify_on_hook_fail) );
  %event_end_notify_on_hook_success = map { $_ => 1 }
    split( /\s*,\s*/, lc($event_end_notify_on_hook_success) );

  $event_end_notify_if_start_success = config_get_val(
    $config, 'hook',
    'event_end_notify_if_start_success',
    DEFAULT_EVENT_END_NOTIFY_IF_START_SUCCESS
  );

  $use_hook_description =
    config_get_val( $config, 'hook', 'use_hook_description',
    DEFAULT_HOOK_USE_HOOK_DESCRIPTION );
  $keep_frame_match_type =
    config_get_val( $config, 'hook', 'keep_frame_match_type',
    DEFAULT_HOOK_KEEP_FRAME_MATCH_TYPE );
  $hook_skip_monitors = config_get_val( $config, 'hook', 'hook_skip_monitors' );
  %hook_skip_monitors = map { $_ => !undef } split( ',', $hook_skip_monitors );
  $hook_pass_image_path =
    config_get_val( $config, 'hook', 'hook_pass_image_path' );

}

# helper routines to print config status in help
sub yes_or_no {
  return $_[0] ? 'yes' : 'no';
}

sub value_or_undefined {
  return $_[0] || '(undefined)';
}

sub present_or_not {
  return $_[0] ? '(defined)' : '(undefined)';
}

sub print_config {
  my $abs_config_file = File::Spec->rel2abs($config_file);

  print(
    <<"EOF"

${\(
  $config_file_present ?
  "Configuration (read $abs_config_file)" :
  "Default configuration ($abs_config_file doesn't exist)"
)}:

Secrets file.......................... ${\(value_or_undefined($secrets_filename))}
Base data path........................ ${\(value_or_undefined($base_data_path))}
Restart interval (secs)............... ${\(value_or_undefined($restart_interval))}

Use admin interface .................. ${\(yes_or_no($use_escontrol_interface))}
Admin interface password.............. ${\(present_or_not($escontrol_interface_password))}
Admin interface persistence file ..... ${\(value_or_undefined($escontrol_interface_file))}

Port ................................. ${\(value_or_undefined($port))}
Address .............................. ${\(value_or_undefined($address))}
Event check interval ................. ${\(value_or_undefined($event_check_interval))}
Monitor reload interval .............. ${\(value_or_undefined($monitor_reload_interval))}
Skipped monitors...................... ${\(value_or_undefined($skip_monitors))}

Auth enabled ......................... ${\(yes_or_no($auth_enabled))}
Auth timeout ......................... ${\(value_or_undefined($auth_timeout))}

Use API Push.......................... ${\(yes_or_no($use_api_push))}
API Push Script....................... ${\(value_or_undefined($api_push_script))}

Use FCM .............................. ${\(yes_or_no($use_fcm))}
FCM Date Format....................... ${\(value_or_undefined($fcm_date_format))}
FCM API key .......................... ${\(present_or_not($fcm_api_key))}
Token file ........................... ${\(value_or_undefined($token_file))}

Use MQTT ............................. ${\(yes_or_no($use_mqtt))}
MQTT Server .......................... ${\(value_or_undefined($mqtt_server))}
MQTT Topic ........................... ${\(value_or_undefined($mqtt_topic))}
MQTT Username ........................ ${\(value_or_undefined($mqtt_username))}
MQTT Password ........................ ${\(present_or_not($mqtt_password))}
MQTT Retain .......................... ${\(yes_or_no($mqtt_retain))}
MQTT Tick Interval ................... ${\(value_or_undefined($mqtt_tick_interval))}

SSL enabled .......................... ${\(yes_or_no($ssl_enabled))}
SSL cert file ........................ ${\(value_or_undefined($ssl_cert_file))}
SSL key file ......................... ${\(value_or_undefined($ssl_key_file))}

Verbose .............................. ${\(yes_or_no($console_logs))}
ES Debug level.........................${\(value_or_undefined($es_debug_level))}
Read alarm cause ..................... ${\(yes_or_no($read_alarm_cause))}
Tag alarm event id ................... ${\(yes_or_no($tag_alarm_event_id))}
Use custom notification sound ........ ${\(yes_or_no($use_custom_notification_sound))}
Send event end notification............${\(yes_or_no($send_event_end_notification))}

Use Hooks............................. ${\(yes_or_no($use_hooks))}
Hook Script on Event Start ........... ${\(value_or_undefined($event_start_hook))}
User Script on Event Start.............${\(value_or_undefined($event_start_hook_notify_userscript))}
Hook Script on Event End.............. ${\(value_or_undefined($event_end_hook))}
User Script on Event End.............${\(value_or_undefined($event_end_hook_notify_userscript))}
Hook Skipped monitors................. ${\(value_or_undefined($hook_skip_monitors))}

Notify on Event Start (hook success).. ${\(value_or_undefined($event_start_notify_on_hook_success))}
Notify on Event Start (hook fail)..... ${\(value_or_undefined($event_start_notify_on_hook_fail))}
Notify on Event End (hook success).... ${\(value_or_undefined($event_end_notify_on_hook_success))}
Notify on Event End (hook fail)....... ${\(value_or_undefined($event_end_notify_on_hook_fail))}
Notify End only if Start success...... ${\(yes_or_no($event_end_notify_if_start_success))}

Use Hook Description.................. ${\(yes_or_no($use_hook_description))}
Keep frame match type................. ${\(yes_or_no($keep_frame_match_type))}
Store Frame in ZM......................${\(yes_or_no($hook_pass_image_path))}

Picture URL .......................... ${\(value_or_undefined($picture_url))}
Include picture....................... ${\(yes_or_no($include_picture))}
Picture username ..................... ${\(value_or_undefined($picture_portal_username))}
Picture password ..................... ${\(present_or_not($picture_portal_password))}

EOF
  );
}

exit( print_config() ) if $check_config;
print_config() if $console_logs;

# Lets now load all the optional dependent libraries in a failsafe way

# Fetch whatever options are available from CLI arguments.

if ($use_fcm) {
  if ( !try_use('LWP::UserAgent')
    || !try_use('URI::URL')
    || !try_use('LWP::Protocol::https') )
  {
    Fatal(
      'FCM push mode needs LWP::Protocol::https, LWP::UserAgent and URI::URL perl packages installed'
    );
  }
  else {
    printInfo('Push enabled via FCM');
  }

}
else {
  printInfo('FCM disabled.');
}

if ($use_api_push) {
  printInfo("Pushes will be sent through APIs and will use $api_push_script");
}

if ($use_mqtt) {
  if ( !try_use('Net::MQTT::Simple') ) {
    Fatal('Net::MQTT::Simple  missing');
    exit(-1);
  }
  printInfo('MQTT Enabled');

}
else {
  printInfo('MQTT Disabled');
}

# ==========================================================================
#
# Don't change anything below here
#
# ==========================================================================

use ZoneMinder;
use POSIX;
use DBI;

$ENV{PATH} = '/bin:/usr/bin';
$ENV{SHELL} = '/bin/sh' if exists $ENV{SHELL};
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

sub Usage {
  print("This daemon is not meant to be invoked from command line\n");
  exit(-1);
}

sub logrot {
  logReinit();
  printDebug('log rotate HUP handler processed, logs re-inited',1);

}

# https://docstore.mik.ua/orelly/perl4/cook/ch07_24.htm
sub sysreadline(*;$) {
  my ( $handle, $timeout ) = @_;
  $handle = qualify_to_ref( $handle, caller() );
  my $infinitely_patient = ( @_ == 1 || $timeout < 0 );
  my $start_time         = time();
  my $selector           = IO::Select->new();
  $selector->add($handle);
  my $line = "";
SLEEP:

  until ( at_eol($line) ) {
    unless ($infinitely_patient) {
      return $line if time() > ( $start_time + $timeout );
    }

    # sleep only 1 second before checking again
    next SLEEP unless $selector->can_read(1.0);
  INPUT_READY:
    while ( $selector->can_read(0.0) ) {
      my $was_blocking = $handle->blocking(0);
    CHAR: while ( sysread( $handle, my $nextbyte, 1 ) ) {
        $line .= $nextbyte;
        last CHAR if $nextbyte eq "\n";
      }
      $handle->blocking($was_blocking);

      # if incomplete line, keep trying
      next SLEEP unless at_eol($line);
      last INPUT_READY;
    }
  }
  return $line;
}
sub at_eol($) { $_[0] =~ /\n\z/ }

sub REAPER {

  # don't mess up return codes for back ticks
  local ( $!, $? );
  my $pid;
  $pid = waitpid( -1, &WNOHANG );
  if ( $pid == -1 ) {    # no child waiting. Ignore it.
  }
  elsif ( WIFEXITED($?) ) {
    printDebug("REAPER: acknowledged child $pid exiting\n",2);
  }
  else {
    printDebug("REAPER: False alarm on $pid",2);
  }
  $SIG{CHLD} = \&REAPER;    # install *after* calling waitpid
}

logInit();
logSetSignal();

$SIG{HUP} = \&logrot;

#$SIG{CHLD} = \&REAPER;
$SIG{CHLD} = "IGNORE";

#$SIG{CHLD} = 'DEFAULT';

my $dbh = zmDbConnect();
my %monitors=();
my %active_events       = ();
my $monitor_reload_time = 0;
my $es_start_time       = time();
my $apns_feedback_time  = 0;
my $proxy_reach_time    = 0;
my $wss;
my @events             = ();
my @active_connections = ();
my $wss;
my $zmdc_active = 0;

# Main entry point
#

printInfo("|------- Starting ES version: $app_version ---------|");
printDebug( "Started with: perl:" . $^X . " and command:" . $0 ,1);

my $zmdc_status = `zmdc.pl status zmeventnotification.pl`;
if ( index( $zmdc_status, 'running since' ) != -1 ) {
  $zmdc_active = 1;
  printDebug(
    'ES invoked via ZMDC. Will exit when needed and have zmdc restart it',1);
}
else {
  printDebug('ES invoked manually. Will handle restarts ourselves',1);
}

printWarning(
  'WARNING: SSL is disabled, which means all traffic will be unencrypted')
  unless $ssl_enabled;

pipe( READER, WRITER ) || die "pipe failed: $!";
WRITER->autoflush(1);
my ( $rin, $rout ) = ('');
vec( $rin, fileno(READER), 1 ) = 1;
printDebug('Parent<--Child pipe ready',2);

if ($use_fcm) {
  my $dir = dirname($token_file);
  if ( !-d $dir ) {

    printDebug("Creating $dir to store FCM tokens",1);
    mkdir $dir;
  }
}

printInfo("Event Notification daemon v $app_version starting\n");
loadPredefinedConnections();
initSocketServer();
printInfo("Event Notification daemon exiting\n");
exit();

# Try to load a perl module
# and if it is not available
# generate a log

sub try_use {
  my $module = shift;
  eval("use $module");
  return ( $@ ? 0 : 1 );
}

# ZM logger print and optionally console print
sub printDebug {
  my $str = shift;
  my $level = shift;
  $level = $es_debug_level if not defined $level;
  return if $es_debug_level < $level;
  my $now = strftime( '%Y-%m-%d,%H:%M:%S', localtime );
  $str = $prefix . ' ' . $str;
  print( "CONSOLE DBG-$level:", $now, " ", $str, "\n" ) if $console_logs;

  Debug($str);
}

sub printInfo {
  my $str = shift;
  my $now = strftime( '%Y-%m-%d,%H:%M:%S', localtime );
  $str = $prefix . ' ' . $str;
  print( 'CONSOLE INF:', $now, " ", $str, "\n" ) if $console_logs;

  Info($str);
}

sub printWarning {
  my $str = shift;
  my $now = strftime( '%Y-%m-%d,%H:%M:%S', localtime );
  $str = $prefix . ' ' . $str;
  print( 'CONSOLE WAR:', $now, " ", $str, "\n" ) if $console_logs;
  Warning($str);
}

sub printError {
  my $str = shift;
  my $now = strftime( '%Y-%m-%d,%H:%M:%S', localtime );
  $str = $prefix . ' ' . $str;
  print( 'CONSOLE ERR:', $now, " ", $str, "\n" ) if $console_logs;
  Error($str);
}

# splits JSON string from detection title string
sub parseDetectResults {
  my $results = shift;
  my ( $txt, $jsonstring ) = split( '--SPLIT--', $results );

  $jsonstring = '[]' if ( !$jsonstring );
  printDebug("parse of hook:$txt and $jsonstring",2);
  return ( $txt, $jsonstring );
}

sub saveEsControlSettings() {
  if ( !$use_escontrol_interface ) {
    printDebug('ESCONTROL_INTERFACE is disabled. Not saving control data',1);

  }
  return if ( !$use_escontrol_interface );
  printDebug(
    "ESCONTROL_INTERFACE: Saving admin interfaces to $escontrol_interface_file",1
  );
  store( \%escontrol_interface_settings, $escontrol_interface_file )
    or Fatal("Error writing to $escontrol_interface_file: $!");
}

sub loadEsControlSettings() {

  if ( !$use_escontrol_interface ) {
    printDebug('ESCONTROL_INTERFACE is disabled. Not loading control data',1);
    return;
  }
  printDebug(
    "ESCONTROL_INTERFACE: Loading persistent admin interface settings from $escontrol_interface_file",1
  );
  if ( !-f $escontrol_interface_file ) {
    printDebug(
      'ESCONTROL_INTERFACE: admin interface file does not exist, creating...',1);
    saveEsControlSettings();

  }
  else {
    %escontrol_interface_settings = %{ retrieve($escontrol_interface_file) };
    my $json = encode_json( \%escontrol_interface_settings );
    printDebug("ESCONTROL_INTERFACE: Loaded parameters: $json",2);
  }

}

# checks to see if notifications are muted or enabled for this monitor
sub getNotificationStatusEsControl {
  my $id = shift;
  if ( !exists $escontrol_interface_settings{notifications}{$id} ) {
    printError(
      "Hmm, Monitor:$id does not exist in control interface, treating it as force notify..."
    );
    return ESCONTROL_FORCE_NOTIFY;
  }
  else {
    # printDebug( "ESCONTROL: Notification for Monitor:$id is "
    #     . $escontrol_interface_settings{notifications}{$id} );
    return $escontrol_interface_settings{notifications}{$id};
  }

}

sub populateEsControlNotification {

  # we need to update notifications in admin interface
  if ($use_escontrol_interface) {
    my $found = 0;
    foreach my $monitor ( values(%monitors) ) {
      my $id = $monitor->{Id};
      if ( !exists $escontrol_interface_settings{notifications}{$id} ) {
        $escontrol_interface_settings{notifications}{$id} =
          ESCONTROL_DEFAULT_NOTIFY;
        $found = 1;
        printDebug(
          "ESCONTROL_INTERFACE: Discovered new monitor:$id, settings notification to ESCONTROL_DEFAULT_NOTIFY",1
        );
      }

    }
    saveEsControlSettings() if ($found);
  }
}

# This handles admin commands for a connection
sub processEsControlCommand {

  return if ( !$use_escontrol_interface );

  my ( $json, $conn ) = @_;

  my $obj = getObjectForConn($conn);
  if ( !$obj ) {
    printError('ESCONTROL error matching connection to object');
    return;
  }

  if ( $obj->{category} ne 'escontrol' ) {

    my $str = encode_json(
      { event   => 'escontrol',
        type    => 'command',
        status  => 'Fail',
        reason  => 'NOTCONTROL',
        request => $json
      }
    );
    eval { $conn->send_utf8($str); };
    if ($@) {
      Error("Error sending NOT CONTROL: $@");

    }

    return;

  }

  if ( !$json->{data} ) {
    my $str = encode_json(
      { event  => 'escontrol',
        type   => 'command',
        status => 'Fail',
        reason => 'NODATA'
      }
    );
    eval { $conn->send_utf8($str); };
    if ($@) {
      Error("Error sending ADMIN NO DATA: $@");

    }

    return;
  }

  if ( $json->{data}->{command} eq 'get' ) {

    my $str = encode_json(
      { event    => 'escontrol',
        type     => '',
        status   => 'Success',
        request  => $json,
        response => encode_json( \%escontrol_interface_settings )
      }
    );
    eval { $conn->send_utf8($str); };
    if ($@) {
      Error("Error sending message: $@");

    }

  }

  elsif ( $json->{data}->{command} eq 'mute' ) {
    printInfo('ESCONTROL: Admin Interface: Mute notifications');

    my @mids;
    if ( $json->{data}->{monitors} ) {
      @mids = @{ $json->{data}->{monitors} };
    }
    else {
      @mids = getAllMonitorIds();
    }

    foreach my $mid (@mids) {
      $escontrol_interface_settings{notifications}{$mid} = ESCONTROL_FORCE_MUTE;
      printDebug(
        "ESCONTROL: setting notification for Mid:$mid to ESCONTROL_FORCE_MUTE",1);
    }

    saveEsControlSettings();
    my $str = encode_json(
      { event   => 'escontrol',
        type    => '',
        status  => 'Success',
        request => $json
      }
    );
    eval { $conn->send_utf8($str); };
    if ($@) {
      Error("Error sending message: $@");

    }

  }
  elsif ( $json->{data}->{command} eq 'unmute' ) {
    printInfo('ESCONTROL: Admin Interface: Unmute notifications');

    my @mids;
    if ( $json->{data}->{monitors} ) {
      @mids = @{ $json->{data}->{monitors} };
    }
    else {
      @mids = getAllMonitorIds();
    }

    foreach my $mid (@mids) {
      $escontrol_interface_settings{notifications}{$mid} =
        ESCONTROL_FORCE_NOTIFY;
      printDebug(
        "ESCONTROL: setting notification for Mid:$mid to ESCONTROL_FORCE_NOTIFY",2
      );
    }

    saveEsControlSettings();
    my $str = encode_json(
      { event   => 'escontrol',
        type    => '',
        status  => 'Success',
        request => $json
      }
    );
    eval { $conn->send_utf8($str); };
    if ($@) {
      Error("Error sending message: $@");
    }

  }
  elsif ( $json->{data}->{command} eq 'edit' ) {
    my $key = $json->{data}->{key};
    my $val = $json->{data}->{val};
    printInfo("ESCONTROL_INTERFACE: Change $key to $val");
    $escontrol_interface_settings{$key} = $val;
    saveEsControlSettings();
    printInfo('ESCONTROL_INTERFACE: --- Doing a complete reload of config --');
    loadEsConfigSettings();

    my $str = encode_json(
      { event   => 'escontrol',
        type    => '',
        status  => 'Success',
        request => $json
      }
    );
    eval { $conn->send_utf8($str); };
    if ($@) {
      Error("Error sending message: $@");
    }

  }
  elsif ( $json->{data}->{command} eq 'restart' ) {
    printInfo('ES_CONTROL: restart ES');

    my $str = encode_json(
      { event   => 'escontrol',
        type    => 'command',
        status  => 'Success',
        request => $json
      }
    );
    eval { $conn->send_utf8($str); };
    if ($@) {
      Error("Error sending message: $@");
    }
    restartES();
  }
  elsif ( $json->{data}->{command} eq 'reset' ) {
    printInfo('ES_CONTROL: reset admin commands');

    my $str = encode_json(
      { event   => 'escontrol',
        type    => 'command',
        status  => 'Success',
        request => $json
      }
    );
    eval { $conn->send_utf8($str); };
    if ($@) {
      Error("Error sending message: $@");
    }
    %escontrol_interface_settings = ( notifications => {} );
    populateEsControlNotification();
    saveEsControlSettings();
    printInfo('ESCONTROL_INTERFACE: --- Doing a complete reload of config --');
    loadEsConfigSettings();
  }
  else {
    my $str = encode_json(
      { event   => $json->{escontrol},
        type    => 'command',
        status  => 'Fail',
        reason  => 'NOTSUPPORTED',
        request => $json
      }
    );
    eval { $conn->send_utf8($str); };
    if ($@) {
      Error("Error sending NOTSUPPORTED: $@");

    }

  }

}

# This function uses shared memory polling to check if
# ZM reported any new events. If it does find events
# then the details are packaged into the events array
# so they can be JSONified and sent out

# Output:
#    {Name => Name of monitor, MonitorId => ID of monitor, EventId => Event ID, Cause=> Cause text ofƒ alarm}
# a) List of events in the @events array with the following structure per event:
# b) A CONCATENATED list of events in $alarm_header_display for convenience
# c) A CONCATENATED list of monitor IDs in $alarm_mid

sub checkNewEvents() {

  my $eventFound = 0;
  my @newEvents  = ();

  #printDebug("inside checkNewEvents()");
  if ( ( time() - $monitor_reload_time ) > $monitor_reload_interval ) {

    # this means we have hit the reload monitor timeframe
    my $len = scalar @active_connections;
    printDebug( 'Total event client connections: ' . $len . "\n",1 );
    my $ndx = 1;
    foreach (@active_connections) {

      my $cip = '(none)';
      if ( exists $_->{conn} ) {
        $cip = $_->{conn}->ip();
      }
      printDebug( '-->checkNewEvents: Connection '
          . $ndx
          . ': ID->'
          . $_->{id} . ' IP->'
          . $cip
          . ' Token->:...'
          . substr( $_->{token}, -10 )
          . ' Plat:'
          . $_->{platform}
          . ' Push:'
          . $_->{pushstate},1 );
      $ndx++;
    }
    
    foreach my $monitor ( values(%monitors) ) {
      zmMemInvalidate($monitor);
    }
    loadMonitors();
  }
  
  # loop through all monitors getting SHM state
  foreach my $monitor ( values(%monitors) ) {
    my $alarm_cause = '';
    if ( !zmMemVerify($monitor) ) {

      Warning( ' Memory verify failed for '
          . $monitor->{Name} . '(id:'
          . $monitor->{Id}
          . ')' );
      loadMonitor($monitor);
      next;
    }

    my ( $state, $current_event, $trigger_cause, $trigger_text ) = zmMemRead(
      $monitor,
      [ 'shared_data:state',          'shared_data:last_event',
        'trigger_data:trigger_cause', 'trigger_data:trigger_text',
      ]
    );

    next if ( !$current_event );    # will it ever happen?

    $alarm_cause = zmMemRead( $monitor, 'shared_data:alarm_cause' )
      if ($read_alarm_cause);
    $alarm_cause = $trigger_cause
      if ( defined($trigger_cause)
      && $alarm_cause eq ''
      && $trigger_cause ne '' );

    my $mid = $monitor->{Id};

    # Alert only happens after alarm. The state before alarm
    # is STATE_PRE_ALERT. This is needed to catch alarms
    # that occur in < polling time of ES and then moves to ALERT
    if ( $state == STATE_ALARM || $state == STATE_ALERT ) {  
   
      if  (!$active_events{$mid}->{$current_event}) {

        if ($active_events{$mid}->{last_event_processed} >= $current_event) {
          printDebug ("Discarding new event id: $current_event as last processed eid for this monitor is: ".$active_events{$mid}->{last_event_processed},2);
          next;

        }
         
         
       
        # this means we haven't previously worked on this alarm
        # so create an event start object for this monitor
        
        $eventFound++;

        # First we need to close any other open events for this monitor
        foreach my $ev ( keys %{ $active_events{$mid} } ) {
          next if $ev == 'last_event_processed';
          if ( !$active_events{$mid}->{$ev}->{End} ) {
            printDebug(
              "Closing unclosed event:$ev of Monitor:$mid as we are in a new event",2
            );

            $active_events{$mid}->{$ev}->{End} = {
              State => 'pending',
              Time  => time(),
              Cause => getNotesFromEventDB($ev)

              }

          }
        }

        # add this new event to active events
        $active_events{$mid}->{$current_event} = {
          MonitorId   => $monitor->{Id},
          MonitorName => $monitor->{Name},
          EventId     => $current_event,
          Start       => {
            State => 'pending',
            Time  => time(),
            Cause => $alarm_cause,
          },
        };

        #print Dumper($active_events{$mid}->{$current_event});

        printInfo( "New event $current_event reported for Monitor:"
            . $monitor->{Id}
            . ' (Name:'
            . $monitor->{Name} . ') '
            . $alarm_cause
            . "[last processed eid:".$active_events{$mid}->{last_event_processed}."]" );

        push @newEvents,
          {
          Alarm      => $active_events{$mid}->{$current_event},
          MonitorObj => $monitor
          };
        $active_events{$mid}->{last_event_processed} = $current_event;
      }
      else {
 # state alarm and it is present in the active event list, so we've worked on it
        printDebug(
          "We've already worked on Monitor:$mid, Event:$current_event, not doing anything more",2
        );
      }
    }

  }

  printDebug("checkEvents() new events found=$eventFound",2);
  return (@newEvents);
}

sub loadMonitor {
  my $monitor = shift;
  printDebug( "loadMonitor: re-loading monitor " . $monitor->{Name},1 );
  zmMemInvalidate($monitor);
  if ( zmMemVerify($monitor) ) {    # This will re-init shared memory
    $monitor->{LastState} = zmGetMonitorState($monitor);
    $monitor->{LastEvent} = zmGetLastEvent($monitor);
    return 1;
  }
  return 0;                         # coming here means verify failed
}

# Refreshes list of monitors from DB
#
sub loadMonitors {
  printInfo("Re-loading monitors");
  $monitor_reload_time = time();

  my $sql = 'SELECT * FROM `Monitors`
        WHERE find_in_set( `Function`, \'Modect,Mocord,Nodect\' )'
    . ( $Config{ZM_SERVER_ID} ? 'AND `ServerId`=?' : '' );
  my $sth = $dbh->prepare_cached($sql)
    or Fatal( "Can't prepare '$sql': " . $dbh->errstr() );
  my $res = $sth->execute( $Config{ZM_SERVER_ID} ? $Config{ZM_SERVER_ID} : () )
    or Fatal( "Can't execute: " . $sth->errstr() );
  while ( my $monitor = $sth->fetchrow_hashref() ) {

    if ( $skip_monitors{ $monitor->{Id} } ) {
      printDebug("$$monitor{Id} is in skip list, not going to process",1);
      next;
    }

    if ( zmMemVerify($monitor) ) {
      $monitor->{LastState}        = zmGetMonitorState($monitor);
      $monitor->{LastEvent}        = zmGetLastEvent($monitor);
      $monitors{ $monitor->{Id} } = $monitor;
    }
    $monitors{ $monitor->{Id} } = $monitor;
    printDebug ("Loading ".$monitor->{Name},1);
    
  }    # end while fetchrow
  

  populateEsControlNotification();
  saveEsControlSettings();

}

# returns all monitor IDs
sub getAllMonitorIds {
  my @mons = ();

  foreach my $monitor ( values(%monitors) ) {
    my $id = $monitor->{Id};
    push @mons, $id;
  }
  return @mons;
}

# Updated Notes DB of events with detection text
# if available (hook enabled)
sub updateEventinZmDB {
  my ( $eid, $notes ) = @_;
  $notes = $notes . " ";
  printDebug( 'updating Notes clause for Event:' . $eid . ' with:' . $notes,1 );
  my $sql = 'UPDATE Events set Notes=CONCAT(?,Notes) where Id=?';
  my $sth = $dbh->prepare_cached($sql)
    or Fatal( "UpdateEventInZmDB: Can't prepare '$sql': " . $dbh->errstr() );
  my $res = $sth->execute( $notes, $eid )
    or Fatal( "UpdateEventInZmDB: Can't execute: " . $sth->errstr() );
  $sth->finish();

}

sub getNotesFromEventDB {
  my $eid = shift;
  my $sql = 'SELECT `Notes` from `Events` WHERE `Id`=?';
  my $sth = $dbh->prepare_cached($sql)
    or Fatal( "getNotesFromEventDB: Can't prepare '$sql': " . $dbh->errstr() );
  my $res = $sth->execute($eid)
    or Fatal( "getNotesFromEventDB: Can't execute: " . $sth->errstr() );
  my $notes = $sth->fetchrow_hashref();
  $sth->finish();
  
  return $notes->{Notes};
}

# This function compares the password provided over websockets
# to the password stored in the ZM MYSQL DB

sub validateAuth {

  my ( $u, $p, $c ) = @_;

  # not an ES control auth
  if ( $c eq 'normal' ) {
    return 1 unless $auth_enabled;

    return 0 if ( $u eq '' || $p eq '' );
    my $sql = 'select `Password` from `Users` where `Username`=?';
    my $sth = $dbh->prepare_cached($sql)
      or Fatal( "Can't prepare '$sql': " . $dbh->errstr() );
    my $res = $sth->execute($u)
      or Fatal( "Can't execute: " . $sth->errstr() );
    my $state = $sth->fetchrow_hashref();
    $sth->finish();

    if ($state) {
      my $scheme = substr( $state->{Password}, 0, 1 );
      if ( $scheme eq '*' ) {    # mysql decode
        printDebug('Comparing using mysql hash',2);
        if ( !try_use('Crypt::MySQL qw(password password41)') ) {
          Fatal('Crypt::MySQL  missing, cannot validate password');
          return 0;
        }
        my $encryptedPassword = password41($p);
        return $state->{Password} eq $encryptedPassword;
      }
      else {                     # try bcrypt
        if ( !try_use('Crypt::Eksblowfish::Bcrypt') ) {
          Fatal('Crypt::Eksblowfish::Bcrypt missing, cannot validate password');
          return 0;
        }
        my $saved_pass = $state->{Password};

        # perl bcrypt libs can't handle $2b$ or $2y$
        $saved_pass =~ s/^\$2.\$/\$2a\$/;
        my $new_hash = Crypt::Eksblowfish::Bcrypt::bcrypt( $p, $saved_pass );
        printDebug("Comparing using bcrypt $new_hash to $saved_pass",2);
        return $new_hash eq $saved_pass;
      }
    }
    else {
      return 0;
    }

  }
  else {
    # admin category
    printDebug('Detected escontrol interface auth',1);
    return ( $p eq $escontrol_interface_password )
      && ($use_escontrol_interface);

  }
}

# deletes a token - invoked if FCM responds with an incorrect token error
sub deleteFCMToken {
  my $dtoken = shift;
  printDebug( 'DeleteToken called with ...' . substr( $dtoken, -10 ),2 );
  return if ( !-f $token_file );

  open( my $fh, '<', $token_file ) or Fatal("Error opening $token_file: $!");
  chomp( my @lines = <$fh> );
  close($fh);
  my @uniquetokens = uniq(@lines);

  open( $fh, '>', $token_file ) or Fatal("Error opening $token_file: $!");

  foreach (@uniquetokens) {
    my ( $token, $monlist, $intlist, $platform, $pushstate ) =
      rsplit( qr/:/, $_, 5 );    #split (":",$_);
    next if ( $_ eq '' || $token eq $dtoken );
    print $fh "$_\n";

    #print "delete: $row\n";
    my $tod = gettimeofday;
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
      };

  }
  close($fh);
}

# Sends a push notification to the mqtt Broker
# called in a forked process
sub sendOverMQTTBroker {

  my $alarm      = shift;
  my $ac         = shift;
  my $event_type = shift;
  my $resCode    = shift;

  my $json;

# only remove if not removed before. If you are sending over multiple channels, it may have already been stripped
  $alarm->{Cause} = substr( $alarm->{Cause}, 4 )
    if ( !$keep_frame_match_type && $alarm->{Cause} =~ /^\[.\]/ );
  my $description =
    $alarm->{Name} . ':(' . $alarm->{EventId} . ') ' . $alarm->{Cause};

  $description = 'Ended:' . $description if ( $event_type eq 'event_end' );

  $json = encode_json(
    { monitor   => $alarm->{MonitorId},
      name      => $description,
      state     => 'alarm',
      eventid   => $alarm->{EventId},
      hookvalue => $resCode,
      eventtype => $event_type,
      detection => $alarm->{DetectionJson}
    }
  );

  printDebug( 'requesting MQTT Publishing Job for EID:' . $alarm->{EventId} ,2);
  my $topic = join( '/', $mqtt_topic, $alarm->{MonitorId} );

  # Net:MQTT:Simple does not appear to be thread/fork safe so send message to
  # parent process via pipe to create a mqtt_publish job.
  print WRITER 'mqtt_publish--TYPE--'
    . $ac->{id}
    . '--SPLIT--'
    . $topic
    . '--SPLIT--'
    . $json . "\n";

}

# called in a forked process
sub sendOverWebSocket {

# We can't send websocket data in a fork. WSS contains user space crypt data that
# goes out of sync with the parent. So we use a parent pipe
  my $alarm      = shift;
  my $ac         = shift;
  my $event_type = shift;
  my $resCode    = shift;

# only remove if not removed before. If you are sending over multiple channels, it may have already been stripped
  $alarm->{Cause} = substr( $alarm->{Cause}, 4 )
    if ( !$keep_frame_match_type && $alarm->{Cause} =~ /^\[.\]/ );

  $alarm->{Cause} = 'End:' . $alarm->{Cause}
    if ( $event_type eq 'event_end' );
  my $str = encode_json(
    { event  => 'alarm',
      type   => '',
      status => 'Success',
      events => [$alarm]
    }
  );
  printDebug( 'Child: posting job to send out message to id:'
      . $ac->{id} . '->'
      . $ac->{conn}->ip() . ':'
      . $ac->{conn}->port(),2 );
  print WRITER 'message--TYPE--' . $ac->{id} . '--SPLIT--' . $str . "\n";

}

# Sends a push notification to FCM
# called in a forked process
sub sendOverFCM {

  my $alarm      = shift;
  my $obj        = shift;
  my $event_type = shift;
  my $resCode    = shift;

  my $mid   = $alarm->{MonitorId};
  my $eid   = $alarm->{EventId};
  my $mname = $alarm->{Name};

  my $pic = $picture_url =~ s/EVENTID/$eid/gr;
  if ( $resCode == 1 ) {
    printDebug(
      'FCM called when hook failed, so making sure we do not use objdetect in url',2
    );
    $pic = $pic =~ s/objdetect/snapshot/gr;
  }

  if ( !$event_start_hook || !$use_hooks ) {
    printDebug(
      'FCM called when there is no start hook/or hooks are disabled, so making sure we do not use objdetect in url',2
    );
    $pic = $pic =~ s/objdetect/snapshot/gr;
  }

  $pic = $pic . '&username=' . $picture_portal_username
    if ($picture_portal_username);
  $pic = $pic . '&password=' . uri_escape($picture_portal_password)
    if ($picture_portal_password);

  #printInfo ("Using URL: $pic with password=$picture_portal_password");

  # if we used best match we will use the right image in notification
  if ( substr( $alarm->{Cause}, 0, 3 ) eq '[a]' ) {
    my $npic = $pic =~ s/BESTMATCH/alarm/gr;
    $pic = $npic;
    my $dpic = $pic;
    $dpic =~ s/pass(word)?=(.*?)($|&)/pass$1=xxx$3/g;

    printDebug("Alarm frame matched, changing picture url to:$dpic ",2);
    $alarm->{Cause} = substr( $alarm->{Cause}, 4 )
      if ( !$keep_frame_match_type );

  }
  elsif ( substr( $alarm->{Cause}, 0, 3 ) eq '[s]' ) {
    my $npic = $pic =~ s/BESTMATCH/snapshot/gr;
    $pic = $npic;
    printDebug("Snapshot frame matched, changing picture url to:$pic ",2);
    $alarm->{Cause} = substr( $alarm->{Cause}, 4 )
      if ( !$keep_frame_match_type );
  }
  elsif ( substr( $alarm->{Cause}, 0, 3 ) eq '[x]' ) {
    $alarm->{Cause} = substr( $alarm->{Cause}, 4 )
      if ( !$keep_frame_match_type );
  }

  my $now = strftime( $fcm_date_format, localtime );
  my $body = $alarm->{Cause};
  $body = $body . ' ended' if ( $event_type eq 'event_end' );
  $body = $body . ' at ' . $now;

  my $badge = $obj->{badge} + 1;

  print WRITER 'badge--TYPE--' . $obj->{id} . '--SPLIT--' . $badge . '\n';
  my $uri = 'https://fcm.googleapis.com/fcm/send';
  my $json;

  # use zmNinja FCM key if the user did not override
  my $key   = 'key=' . $fcm_api_key;
  my $title = $mname . ' Alarm';
  $title = $title . ' (' . $eid . ')' if ($tag_alarm_event_id);
  $title = 'Ended:' . $title          if ( $event_type eq 'event_end' );

  my $ios_message = {
    to           => $obj->{token},
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
      summaryText => $eid
    }
  };

  my $android_message = {
    to       => $obj->{token},
    priority => 'high',
    data     => {
      title       => $title,
      message     => $body,
      style       => 'inbox',
      myMessageId => $notId,
      icon        => 'ic_stat_notification',
      mid         => $mid,
      eid         => $eid,
      badge       => $obj->{badge},
      priority    => 1
    }
  };

  if ( $picture_url && $include_picture ) {
    $ios_message->{mutable_content} = \1;

    #$ios_message->{content_available} = \1;
    $ios_message->{data}->{image_url_jpg} = $pic;

    $android_message->{data}->{style}       = 'picture';
    $android_message->{data}->{picture}     = $pic;
    $android_message->{data}->{summaryText} = 'alarmed image';

    #printDebug ("Alarm image for android will be: $pic");
  }

  if ( $obj->{platform} eq 'ios' ) {
    $json = encode_json($ios_message);
  }

  # if I do both, notification icon in Android gets messed up
  else {    # android
    $json  = encode_json($android_message);
    $notId = ( $notId + 1 ) % 100000;

  }

  my $djson = $json;
  $djson =~ s/pass(word)?=(.*?)($|&)/pass$1=xxx$3/g;

  printDebug( "Final JSON being sent is: $djson to token: ..."
      . substr( $obj->{token}, -6 ),2 );
  my $req = HTTP::Request->new( 'POST', $uri );
  $req->header(
    'Content-Type'  => 'application/json',
    'Authorization' => $key
  );
  $req->content($json);
  my $lwp = LWP::UserAgent->new(%ssl_push_opts);
  my $res = $lwp->request($req);
  my $msg;
  my $json_string;

  if ( $res->is_success ) {
    $msg = $res->decoded_content;
    printDebug( 'FCM push message returned a 200 with body ' . $res->content ,1);
    eval { $json_string = decode_json($msg); };
    if ($@) {

      Error("Failed decoding sendFCM Response: $@");
      return;
    }
    if ( $json_string->{failure} eq 1 ) {
      my $reason = $json_string->{results}[0]->{error};
      Error( 'Error sending FCM for token:' . $obj->{token} );
      Error( 'Error value =' . $reason );
      if ( $reason eq 'NotRegistered'
        || $reason eq 'InvalidRegistration' )
      {
        printDebug('Removing this token as FCM doesn\'t recognize it',1);
        deleteFCMToken( $obj->{token} );
      }

    }
  }
  else {
    printError( 'FCM push message Error:' . $res->status_line );
  }

  # send supplementary event data over websocket, same SSL state issue
  # so use a parent pipe
  if ( $obj->{state} == VALID_CONNECTION && exists $obj->{conn} ) {
    my $sup_str = encode_json(
      { event         => 'alarm',
        type          => '',
        status        => 'Success',
        supplementary => 'true',
        events        => [$alarm]
      }
    );
    print WRITER 'message--TYPE--' . $obj->{id} . '--SPLIT--' . $sup_str . "\n";

  }

}

# credit: https://stackoverflow.com/a/52724546/1361529
sub processJobs {

  #printDebug ("Inside processJobs");
  while ( ( my $read_avail = select( $rout = $rin, undef, undef, 0.0 ) ) != 0 )
  {
    #printDebug("processJobs after select");
    if ( $read_avail < 0 ) {
      if ( !$!{EINTR} ) {
        printError("Pipe read error: $read_avail $!");
      }
    }
    elsif ( $read_avail > 0 ) {

      # printDebug("processJobs inside read_avail > 0");
      chomp( my $txt = sysreadline(READER) );
      printDebug("RAW TEXT-->$txt",2);
      my ( $job, $msg ) = split( '--TYPE--', $txt );

      if ( $job eq 'message' ) {
        my ( $id, $tmsg ) = split( '--SPLIT--', $msg );
        printDebug("GOT JOB==>To: $id, message: $tmsg",2);
        foreach (@active_connections) {
          if ( ( $_->{id} eq $id ) && exists $_->{conn} ) {
            my $tip   = $_->{conn}->ip();
            my $tport = $_->{conn}->port();
            printDebug("Sending child message to $tip:$tport...",2);
            eval { $_->{conn}->send_utf8($tmsg); };
            if ($@) {

              printDebug( 'Marking ' . $_->{conn}->ip() . ' as bad socket' ,1);
              $_->{state} = INVALID_CONNECTION;

            }
          }
        }

      }

      # Update badge count of active connection
      elsif ( $job eq 'badge' ) {
        my ( $id, $badge ) = split( '--SPLIT--', $msg );
        printDebug( 'GOT JOB==> Update badge to:' . $badge . ' for id:' . $id,2 );
        foreach (@active_connections) {
          if ( $_->{id} eq $id ) {
            $_->{badge} = $badge;
          }

        }

      }

      # hook script result will be updated in ZM DB
      elsif ( $job eq 'event_description' ) {
        my ( $mid, $eid, $desc ) = split( '--SPLIT--', $msg );
        printDebug( 'Job: Update monitor ' . $mid . ' description:' . $desc,2 );
        updateEventinZmDB( $eid, $desc );

      }

      # marks the latest time an event was sent out. Needed for interval mgmt.
      elsif ( $job eq 'timestamp' ) {
        my ( $id, $mid, $timeval ) = split( '--SPLIT--', $msg );
        printDebug( 'Job: Update last sent timestamp of monitor:'
            . $mid . ' to '
            . $timeval
            . ' for id:'
            . $id ,2);
        foreach (@active_connections) {
          if ( $_->{id} eq $id ) {
            $_->{last_sent}->{$mid} = $timeval;

          }

        }

        #dump(@active_connections);
      }
      elsif ( $job eq 'active_event_update' ) {
        my ( $mid, $eid, $type, $key, $val ) = split( '--SPLIT--', $msg );
        printDebug(
          "Job: Update active_event eid:$eid, mid:$mid, type:$type, field:$key to: $val",2
        );
        $active_events{$mid}->{$eid}->{$type}->{State} = $val
          if ( $key eq 'State' );
        if ( $key eq 'Cause' ) {
          my ( $causeTxt, $causeJson ) = split( '--JSON--', $val );
          $active_events{$mid}->{$eid}->{$type}->{Cause} = $causeTxt;

          # if detection is not used, this may be empty
          $causeJson = '[]' if ( !$causeJson );
          $active_events{$mid}->{$eid}->{$type}->{DetectionJson} =
            decode_json($causeJson);
        }

      }
      elsif ( $job eq 'active_event_delete' ) {
        my ( $mid, $eid ) = split( '--SPLIT--', $msg );
        printDebug("Job: Deleting active_event eid:$eid, mid:$mid",2);
        delete( $active_events{$mid}->{$eid} );
        $child_forks--;
      }
      elsif ( $job eq 'mqtt_publish' ) {
        my ( $id, $topic, $payload ) = split( '--SPLIT--', $msg );
        printDebug("Job: MQTT Publish on topic: $topic",2);
        foreach (@active_connections) {
          if ( ( $_->{id} eq $id ) && exists $_->{mqtt_conn} ) {
            if ( $mqtt_retain ) {
              printDebug("Job: MQTT Publish with retain",2);
              $_->{mqtt_conn}->retain( $topic => $payload );
            }
            else {
              printDebug("Job: MQTT Publish",2);
              $_->{mqtt_conn}->publish( $topic => $payload );
            }
          }
        }
      }
      else {
        printError("Job message [$job] not recognized!");
      }
    }
  }
  # printDebug('Finished processJobs()');
}

# returns extra fields associated to a connection
sub getConnFields {
  my $conn    = shift;
  my $matched = "";
  foreach (@active_connections) {
    if ( exists $_->{conn} && $_->{conn} == $conn ) {
      $matched = $_->{extra_fields};
      $matched = ' [' . $matched . '] ' if $matched;
      last;

    }
  }
  return $matched;
}

# returns full object that matches a connection
sub getObjectForConn {
  my $conn = shift;
  my $matched;

  foreach (@active_connections) {
    if ( exists $_->{conn} && $_->{conn} == $conn ) {
      $matched = $_;
      last;

    }
  }
  return $matched;
}

# This runs at each tick to purge connections
# that are inactive or have had an error
# This also closes any connection that has not provided
# credentials in the time configured after opening a socket
sub checkConnection {
  foreach (@active_connections) {
    my $curtime = time();
    if ( $_->{state} == PENDING_AUTH ) {

      # This takes care of purging connections that have not authenticated
      if ( $curtime - $_->{time} > $auth_timeout ) {

        # What happens if auth is not provided but device token is registered?
        # It may still be a bogus token, so don't risk keeping connection stored
        if ( exists $_->{conn} ) {
          my $conn = $_->{conn};
          printError( 'Rejecting '
              . $conn->ip()
              . getConnFields($conn)
              . ' - authentication timeout' );
          $_->{state} = PENDING_DELETE;
          my $str = encode_json(
            { event  => 'auth',
              type   => '',
              status => 'Fail',
              reason => 'NOAUTH'
            }
          );
          eval { $_->{conn}->send_utf8($str); };
          if ($@) {
            Error("Error sending NOAUTH: $@");
          }
          $_->{conn}->disconnect();
        }
      }
    }

  }
  @active_connections =
    grep { $_->{state} != PENDING_DELETE } @active_connections;

  my $ac = scalar @active_connections;
  my $fcm_conn =
    scalar grep { $_->{state} == VALID_CONNECTION && $_->{type} == FCM }
    @active_connections;
  my $fcm_no_conn =
    scalar grep { $_->{state} == INVALID_CONNECTION && $_->{type} == FCM }
    @active_connections;
  my $pend_conn =
    scalar grep { $_->{state} == PENDING_AUTH } @active_connections;
  my $mqtt_conn = scalar grep { $_->{type} == MQTT } @active_connections;
  my $web_conn =
    scalar grep { $_->{state} == VALID_CONNECTION && $_->{type} == WEB }
    @active_connections;
  my $web_no_conn =
    scalar grep { $_->{state} == INVALID_CONNECTION && $_->{type} == WEB }
    @active_connections;

  my $escontrol_conn =
    scalar
    grep { $_->{state} == VALID_CONNECTION && $_->{category} == 'escontrol' }
    @active_connections;

  printDebug(
    "After tick: TOTAL: $ac,  ES_CONTROL: $escontrol_conn, FCM+WEB: $fcm_conn, FCM: $fcm_no_conn, WEB: $web_conn, MQTT:$mqtt_conn, invalid WEB: $web_no_conn, PENDING: $pend_conn",3
  );

}

# tokens can have : , so right split - this way I don't break existing token files
# http://stackoverflow.com/a/37870235/1361529
sub rsplit {
  my $pattern = shift(@_);    # Precompiled regex pattern (i.e. qr/pattern/)
  my $expr    = shift(@_);    # String to split
  my $limit   = shift(@_);    # Number of chunks to split into
  map { scalar reverse($_) }
    reverse split( /$pattern/, scalar reverse($expr), $limit );
}

# This function  is called whenever we receive a message from a client
sub processIncomingMessage {
  my ( $conn, $msg ) = @_;

  my $json_string;
  eval { $json_string = decode_json($msg); };
  if ($@) {

    printError("Failed decoding json in processIncomingMessage: $@");
    my $str = encode_json(
      { event  => 'malformed',
        type   => '',
        status => 'Fail',
        reason => 'BADJSON'
      }
    );
    eval { $conn->send_utf8($str); };
    if ($@) {
      Error("Error sending BADJSON: $@");
    }
    return;
  }

  # This event type is when a command related to push notification is received
  if ( ( $json_string->{event} eq "push" ) && !$use_fcm ) {
    my $str = encode_json(
      { event  => 'push',
        type   => '',
        status => 'Fail',
        reason => 'PUSHDISABLED'
      }
    );
    eval { $conn->send_utf8($str); };
    if ($@) {
      Error("Error sending PUSHDISABLED: $@");

    }
    return;
  }

  elsif ( ( $json_string->{event} eq "escontrol" ) ) {
    if ( !$use_escontrol_interface ) {
      my $str = encode_json(
        { event  => 'escontrol',
          type   => '',
          status => 'Fail',
          reason => 'ESCONTROLDISABLED'
        }
      );
      eval { $conn->send_utf8($str); };
      if ($@) {
        Error("Error sending ESCONTROLDISABLED: $@");

      }
      return;
    }
    processEsControlCommand( $json_string, $conn );
    return;

  }

#-----------------------------------------------------------------------------------
# "push" event processing
#-----------------------------------------------------------------------------------
  elsif ( ( $json_string->{event} eq 'push' ) && $use_fcm ) {

# sets the unread event count of events for a specific connection
# the server keeps a tab of # of events it pushes out per connection
# but won't know when the client has read them, so the client call tell the server
# using this message
    if ( $json_string->{data}->{type} eq 'badge' ) {
      foreach (@active_connections) {
        if ( ( exists $_->{conn} )
          && ( $_->{conn}->ip() eq $conn->ip() )
          && ( $_->{conn}->port() eq $conn->port() ) )
        {

          #print "Badge match, setting to 0\n";
          $_->{badge} = $json_string->{data}->{badge};
        }
      }
      return;
    }

    # This sub type is when a device token is registered
    if ( $json_string->{data}->{type} eq 'token' ) {

      # a token must have a platform
      if ( !$json_string->{data}->{platform} ) {
        my $str = encode_json(
          { event  => 'push',
            type   => 'token',
            status => 'Fail',
            reason => 'MISSINGPLATFORM'
          }
        );
        eval { $conn->send_utf8($str); };
        if ($@) {
          Error("Error sending MISSINGPLATFORM: $@");

        }
        return;
      }
      foreach (@active_connections) {

        # this token already exists so we just update records
        if ( $_->{token} eq $json_string->{data}->{token} ) {

          # if the token doesn't belong to the same connection
          # then we have two connections owning the same token
          # so we need to delete the old one. This can happen when you load
          # the token from the persistent file and there is no connection
          # and then the client is loaded
          if (
            ( !exists $_->{conn} )
            || ( $_->{conn}->ip() ne $conn->ip()
              || $_->{conn}->port() ne $conn->port() )
            )
          {
            printDebug('token matched but connection did not',2);
            printDebug( 'Duplicate token found: marking ...'
                . substr( $_->{token}, -10 )
                . ' to be deleted',1 );

            $_->{state} = PENDING_DELETE;

          }
          else    # token matches and connection matches, so it may be an update
          {
            printDebug('token and connection matched',2);
            $_->{type}     = FCM;
            $_->{token}    = $json_string->{data}->{token};
            $_->{platform} = $json_string->{data}->{platform};
            if ( exists( $json_string->{data}->{monlist} )
              && ( $json_string->{data}->{monlist} ne '' ) )
            {
              $_->{monlist} =
                $json_string->{data}->{monlist};
            }
            else {
              $_->{monlist} = '-1';
            }
            if ( exists( $json_string->{data}->{intlist} )
              && ( $json_string->{data}->{intlist} ne '' ) )
            {
              $_->{intlist} =
                $json_string->{data}->{intlist};
            }
            else {
              $_->{intlist} = '-1';
            }
            $_->{pushstate} = $json_string->{data}->{state};
            printDebug( 'Storing token ...'
                . substr( $_->{token}, -10 )
                . ',monlist:'
                . $_->{monlist}
                . ',intlist:'
                . $_->{intlist}
                . ',pushstate:'
                . $_->{pushstate}
                . "\n",1 );
            my ( $emonlist, $eintlist ) = saveFCMTokens(
              $_->{token},    $_->{monlist}, $_->{intlist},
              $_->{platform}, $_->{pushstate}
            );
            $_->{monlist} = $emonlist;
            $_->{intlist} = $eintlist;
          }    # token and conn. matches
        }    # end of token matches
             # The connection matches but the token does not
         # this can happen if this is the first token registration after push notification registration
         # response is received
        if ( ( exists $_->{conn} )
          && ( $_->{conn}->ip() eq $conn->ip() )
          && ( $_->{conn}->port() eq $conn->port() )
          && ( $_->{token} ne $json_string->{data}->{token} ) )
        {
          printDebug(
            'connection matched but token did not. first registration?',2);
          $_->{type}     = FCM;
          $_->{token}    = $json_string->{data}->{token};
          $_->{platform} = $json_string->{data}->{platform};
          $_->{monlist}  = $json_string->{data}->{monlist};
          $_->{intlist}  = $json_string->{data}->{intlist};
          if ( exists( $json_string->{data}->{monlist} )
            && ( $json_string->{data}->{monlist} ne '' ) )
          {
            $_->{monlist} = $json_string->{data}->{monlist};
          }
          else {
            $_->{monlist} = "-1";
          }
          if ( exists( $json_string->{data}->{intlist} )
            && ( $json_string->{data}->{intlist} ne '' ) )
          {
            $_->{intlist} = $json_string->{data}->{intlist};
          }
          else {
            $_->{intlist} = '-1';
          }
          $_->{pushstate} = $json_string->{data}->{state};
          printDebug( 'Storing token ...'
              . substr( $_->{token}, -10 )
              . ',monlist:'
              . $_->{monlist}
              . ',intlist:'
              . $_->{intlist}
              . ',pushstate:'
              . $_->{pushstate}
              . "\n",1 );
          my ( $emonlist, $eintlist ) = saveFCMTokens(
            $_->{token},    $_->{monlist}, $_->{intlist},
            $_->{platform}, $_->{pushstate}
          );
          $_->{monlist} = $emonlist;
          $_->{intlist} = $eintlist;

        }
      }

    }

  }    # event = push
   #-----------------------------------------------------------------------------------
   # "control" event processing
   #-----------------------------------------------------------------------------------
  elsif ( ( $json_string->{event} eq 'control' ) ) {
    if ( $json_string->{data}->{type} eq 'filter' ) {
      if ( !exists( $json_string->{data}->{monlist} ) ) {
        my $str = encode_json(
          { event  => 'control',
            type   => 'filter',
            status => 'Fail',
            reason => 'MISSINGMONITORLIST'
          }
        );
        eval { $conn->send_utf8($str); };
        if ($@) {
          Error("Error sending MISSINGMONITORLIST: $@");

        }
        return;
      }
      if ( !exists( $json_string->{data}->{intlist} ) ) {
        my $str = encode_json(
          { event  => 'control',
            type   => 'filter',
            status => 'Fail',
            reason => 'MISSINGINTERVALLIST'
          }
        );
        eval { $conn->send_utf8($str); };
        if ($@) {
          Error("Error sending MISSINGINTERVALLIST: $@");

        }
        return;
      }
      my $monlist = $json_string->{data}->{monlist};
      my $intlist = $json_string->{data}->{intlist};
      foreach (@active_connections) {
        if ( ( exists $_->{conn} )
          && ( $_->{conn}->ip() eq $conn->ip() )
          && ( $_->{conn}->port() eq $conn->port() ) )
        {

          $_->{monlist} = $monlist;
          $_->{intlist} = $intlist;
          printDebug( 'Contrl: Storing token ...'
              . substr( $_->{token}, -10 )
              . ',monlist:'
              . $_->{monlist}
              . ',intlist:'
              . $_->{intlist}
              . ',pushstate:'
              . $_->{pushstate}
              . "\n" ,2);
          saveFCMTokens(
            $_->{token},    $_->{monlist}, $_->{intlist},
            $_->{platform}, $_->{pushstate}
          );
        }
      }
    }
    if ( $json_string->{data}->{type} eq 'version' ) {
      foreach (@active_connections) {
        if ( ( exists $_->{conn} )
          && ( $_->{conn}->ip() eq $conn->ip() )
          && ( $_->{conn}->port() eq $conn->port() ) )
        {
          my $str = encode_json(
            { event   => 'control',
              type    => 'version',
              status  => 'Success',
              reason  => '',
              version => $app_version
            }
          );
          eval { $_->{conn}->send_utf8($str); };
          if ($@) {
            Error("Error sending version: $@");

          }

        }
      }
    }

  }    # event = control

#-----------------------------------------------------------------------------------
# "auth" event processing
#-----------------------------------------------------------------------------------
# This event type is when a command related to authorization is sent
  elsif ( $json_string->{event} eq 'auth' ) {
    my $uname = $json_string->{data}->{user};
    my $pwd   = $json_string->{data}->{password};

    my $category = 'normal';
    $category = $json_string->{category}
      if ( exists( $json_string->{category} ) );

    if ( $category ne 'normal' && $category ne 'escontrol' ) {
      printDebug("Auth category $category is invalid. Resetting it to 'normal'",1);
      $category = 'normal';
    }

    my $monlist = '';
    my $intlist = '';
    $monlist = $json_string->{data}->{monlist}
      if ( exists( $json_string->{data}->{monlist} ) );
    $intlist = $json_string->{data}->{intlist}
      if ( exists( $json_string->{data}->{intlist} ) );

    foreach (@active_connections) {
      if ( ( exists $_->{conn} )
        && ( $_->{conn}->ip() eq $conn->ip() )
        && ( $_->{conn}->port() eq $conn->port() ) )

        # && ( $_->{state} == PENDING_AUTH ) ) # lets allow multiple auths
      {
        if ( !validateAuth( $uname, $pwd, $category ) ) {

          my $reason = 'BADAUTH';
          $reason = 'ESCONTROLDISABLED'
            if ( $category eq 'escontrol' && !$use_escontrol_interface );

          # bad username or password, so reject and mark for deletion
          my $str = encode_json(
            { event  => 'auth',
              type   => '',
              status => 'Fail',
              reason => $reason
            }
          );
          eval { $_->{conn}->send_utf8($str); };
          if ($@) {
            Error("Error sending BADAUTH: $@");

          }
          printDebug(
            'marking for deletion - bad authentication provided by '
              . $_->{conn}->ip() ,1);
          $_->{state} = PENDING_DELETE;
        }
        else {

          # all good, connection auth was valid
          $_->{category} = $category;

          $_->{state}   = VALID_CONNECTION;
          $_->{monlist} = $monlist;
          $_->{intlist} = $intlist;
          $_->{token}   = '';
          my $str = encode_json(
            { event   => 'auth',
              type    => '',
              status  => 'Success',
              reason  => '',
              version => $app_version
            }
          );
          eval { $_->{conn}->send_utf8($str); };

          if ($@) {
            Error("Error sending auth success: $@");

          }
          printInfo( "Correct authentication provided by " . $_->{conn}->ip() );

        }
      }
    }
  }    # event = auth
  else {
    my $str = encode_json(
      { event  => $json_string->{event},
        type   => '',
        status => 'Fail',
        reason => 'NOTSUPPORTED'
      }
    );
    eval { $_->{conn}->send_utf8($str); };
    if ($@) {
      Error("Error sending NOTSUPPORTED: $@");

    }
  }
}

# Master loader for predefined connections
# As of now, its FCM tokens and MQTT server
sub loadPredefinedConnections {

  # init FCM tokens
  initFCMTokens() if ($use_fcm);
  initMQTT()      if ($use_mqtt);
}

# MQTT init
# currently just a dummy connection for the sake of consistency

sub initMQTT {
  my $mqtt_connection;

  printInfo('Initializing MQTT connection...');

# Note this does not actually connect to the MQTT server. That happens later during publish
  if ( defined $mqtt_username && defined $mqtt_password ) {
    if ( $mqtt_connection = Net::MQTT::Simple->new($mqtt_server) ) {

      # Setting up allow insecure connections
      $ENV{MQTT_SIMPLE_ALLOW_INSECURE_LOGIN} = 'true';

      $mqtt_connection->login( $mqtt_username, $mqtt_password );
      printDebug('Intialized MQTT with auth',1);
    }
  }
  else {
    if ( $mqtt_connection = Net::MQTT::Simple->new($mqtt_server) ) {
      printDebug('Intialized MQTT without auth',1);
    }
  }

  my $id           = gettimeofday;
  my $connect_time = time();
  push @active_connections,
    {
    type         => MQTT,
    state        => VALID_CONNECTION,
    time         => $connect_time,
    monlist      => '',
    intlist      => '',
    last_sent    => {},
    extra_fields => '',
    mqtt_conn    => $mqtt_connection,
    };
}

# loads FCM tokens from file
sub initFCMTokens {
  printDebug('Initializing FCM tokens...',1);
  if ( !-f $token_file ) {
    open( my $foh, '>', $token_file ) or Fatal("Error opening $token_file: $!");
    printDebug( 'Creating ' . $token_file,1 );
    print $foh '';
    close($foh);
  }

  open( my $fh, '<', $token_file ) or Fatal("Error opening $token_file: $!");
  chomp( my @lines = <$fh> );
  close($fh);
  my @uniquetokens = uniq(@lines);

  open( $fh, '>', $token_file ) or Fatal("Error opening $token_file: $!");

  # This makes sure we rewrite the file with
  # unique tokens
  foreach (@uniquetokens) {
    next if ( $_ eq '' );
    print $fh "$_\n";
    my ( $token, $monlist, $intlist, $platform, $pushstate ) =
      rsplit( qr/:/, $_, 5 );    # split (":",$_);
    my $tod = gettimeofday;
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
      };

  }
  close($fh);
}

# When a client sends a token id,
# I store it in the file
# It can be sent multiple times, with or without
# monitor list, so I retain the old monitor
# list if its not supplied. In the case of zmNinja
# tokens are sent without monitor list when the registration
# id is received from apple, so we handle that situation

sub saveFCMTokens {
  return if ( !$use_fcm );
  my $stoken = shift;
  if ( $stoken eq '' ) {
    printDebug('Not saving, no token. Desktop?',2);
    return;
  }
  my $smonlist   = shift;
  my $sintlist   = shift;
  my $splatform  = shift;
  my $spushstate = shift;
  if ( ( $spushstate eq '' ) && ( $stoken ne '' ) ) {
    $spushstate = 'enabled';
    printDebug(
      'Overriding token state, setting to enabled as I got a null with a valid token',1
    );
  }

  printDebug(
    "SaveTokens called with:monlist=$smonlist, intlist=$sintlist, platform=$splatform, push=$spushstate",2
  );

  return if ( $stoken eq '' );
  open( my $fh, '<', $token_file )
    || Fatal( 'Cannot open for read ' . $token_file );
  chomp( my @lines = <$fh> );
  close($fh);
  my @uniquetokens = uniq(@lines);
  my $found        = 0;
  open( my $fh, '>', $token_file )
    || Fatal( 'Cannot open for write ' . $token_file );

  foreach (@uniquetokens) {
    next if ( $_ eq '' );
    my ( $token, $monlist, $intlist, $platform, $pushstate ) =
      rsplit( qr/:/, $_, 5 );    #split (":",$_);
    if ( $token eq $stoken )     # update token in file with new information
    {
      printDebug("token matched, previously stored monlist is: $monlist",1);
      $smonlist   = $monlist   if ( $smonlist eq '-1' );
      $sintlist   = $intlist   if ( $sintlist eq '-1' );
      $spushstate = $pushstate if ( $spushstate eq '' );
      printDebug( 'updating ...'
          . substr( $token, -10 )
          . " with push:$pushstate & monlist:$monlist" ,2);
      print $fh "$stoken:$smonlist:$sintlist:$splatform:$spushstate\n";
      $found = 1;
    }
    else                         # write token as is
    {
      if ( $pushstate eq '' ) {
        $pushstate = 'enabled';
        printDebug('nochange, but pushstate was EMPTY. WHY?',2);
      }
      printDebug("no change - saving token with $pushstate",2);
      print $fh "$token:$monlist:$intlist:$platform:$pushstate\n";
    }

  }

  $smonlist = '' if ( $smonlist eq '-1' );
  $sintlist = '' if ( $sintlist eq '-1' );

  if ( !$found ) {
    printDebug("token not found, creating new record with monlist=$smonlist",1);
    print $fh "$stoken:$smonlist:$sintlist:$splatform:$spushstate\n";
  }
  close($fh);

  return ( $smonlist, $sintlist );

}

# This keeps the latest of any duplicate tokens
# we need to ignore monitor list when we do this
sub uniq {
  my %seen;
  my @array  = reverse @_;    # we want the latest
  my @farray = ();
  foreach (@array) {
    next
      if ( $_ =~ /^\s*$/ )
      ; # skip blank lines - we don't really need this - as token check is later
    my ( $token, $monlist, $intlist, $platform, $pushstate ) =
      rsplit( qr/:/, $_, 5 );    #split (":",$_);
    next if ( $token eq '' );
    if ( ( $pushstate ne 'enabled' ) && ( $pushstate ne 'disabled' ) ) {
      printDebug(
        "huh? uniq read $token,$monlist,$intlist,$platform, $pushstate => forcing state to enabled"
      ,2);
      $pushstate = 'enabled';

    }

    # not interested in monlist & intlist
    if ( !$seen{$token}++ ) {
      push @farray, "$token:$monlist:$intlist:$platform:$pushstate";
    }

  }
  return @farray;

}

# Checks if the monitor for which
# an alarm occurred is part of the monitor list
# for that connection
sub getInterval {
  my $intlist = shift;
  my $monlist = shift;
  my $mid     = shift;

  #print ("getInterval:MID:$mid INT:$intlist AND MON:$monlist\n");
  my @ints = split( ',', $intlist );
  my @mids = split( ',', $monlist );
  my $idx  = -1;
  foreach (@mids) {
    $idx++;

    #print ("Comparing $mid with $_\n");
    if ( $mid eq $_ ) {
      last;
    }
  }

  #print ("RETURNING index:$idx with Value:".$ints[$idx]."\n");
  return $ints[$idx];

}

# Checks if the monitor for which
# an alarm occurred is part of the monitor list
# for that connection
sub isInList {
  my $monlist = shift;
  my $mid     = shift;

  return 1 if ($monlist eq "");

  my @mids = split( ',', $monlist );
  my $found = 0;
  foreach (@mids) {
    if ( $mid eq $_ ) {
      $found = 1;
      last;
    }
  }
  return $found;

}

# Returns an identity string for a connection for display purposes
sub getConnectionIdentity {
  my $obj = shift;

  my $identity = '';

  if ( $obj->{type} == FCM ) {
    if ( exists $obj->{conn} && $obj->{state} != INVALID_CONNECTION ) {
      $identity =
        $obj->{conn}->ip() . ':' . $obj->{conn}->port() . ', ';
    }
    $identity =
      $identity . 'token ending in:...' . substr( $obj->{token}, -10 );
  }
  elsif ( $obj->{type} == WEB ) {
    if ( exists $obj->{conn} ) {
      $identity = $obj->{conn}->ip() . ':' . $obj->{conn}->port();
    }
    else {
      $identity = '(unknown state?)';
    }
  }
  elsif ( $obj->{type} == MQTT ) {
    $identity = 'MQTT ' . $mqtt_server;
  }
  else {
    $identity = 'unknown type(!)';
  }

  return $identity;
}

# Master event send routine. Will invoke different transport APIs as needed based on connection details
sub sendEvent {
  my $alarm      = shift;
  my $ac         = shift;
  my $event_type = shift;
  my $resCode    = shift;    # 0 = on_success, 1 = on_fail

  my $id   = $alarm->{MonitorId};
  my $name = $alarm->{Name};

  if ( !$send_event_end_notification && $event_type eq 'event_end' ) {
    printInfo(
      'Not sending event end notification as send_event_end_notification is no'
    );
    return;
  }

  my $hook = $event_type eq 'event_start' ? $event_start_hook : $event_end_hook;

  my $t   = gettimeofday;
  my $str = encode_json(
    { event  => 'alarm',
      type   => '',
      status => 'Success',
      events => [$alarm]
    }
  );

  if ( $ac->{type} == FCM
    && $ac->{pushstate} ne 'disabled'
    && $ac->{state} != PENDING_AUTH )
  {

    # only send if fcm is an allowed channel
    if ( isAllowedChannel( $event_type, 'fcm', $resCode )
      || !$hook
      || !$use_hooks )
    {
      printInfo("Sending $event_type notification over FCM");
      sendOverFCM( $alarm, $ac, $event_type, $resCode );

    }
    else {
      printInfo(
        "Not sending over FCM as notify filters are on_success:$event_start_notify_on_hook_success and on_fail:$event_end_notify_on_hook_fail"
      );

    }

  }
  elsif ( $ac->{type} == WEB
    && $ac->{state} == VALID_CONNECTION
    && exists $ac->{conn} )
  {

    if ( isAllowedChannel( $event_type, 'web', $resCode )
      || !$hook
      || !$use_hooks )
    {
      printInfo( "Sending $event_type notification for EID:"
          . $alarm->{EventId}
          . 'over web' );
      sendOverWebSocket( $alarm, $ac, $event_type, $resCode );

    }
    else {
      printInfo(
        "Not sending over Web as notify filters are on_success:$event_start_notify_on_hook_success and on_fail:$event_start_notify_on_hook_fail"
      );

    }

  }
  elsif ( $ac->{type} == MQTT ) {

    if ( isAllowedChannel( $event_type, 'mqtt', $resCode )
      || !$hook
      || !$use_hooks )
    {
      printInfo( "Sending $event_type notification for EID:"
          . $alarm->{EventId}
          . ' over MQTT' );
      sendOverMQTTBroker( $alarm, $ac, $event_type, $resCode );
    }
    else {
      printInfo(
        "Not sending over MQTT as notify filters are on_success:$event_start_notify_on_hook_success and on_fail:$event_start_notify_on_hook_fail"
      );

    }
  }

  print WRITER 'timestamp--TYPE--'
    . $ac->{id}
    . '--SPLIT--'
    . $alarm->{MonitorId}
    . '--SPLIT--'
    . $t . "\n";

  printDebug('child finished writing to parent',3);

}

sub isAllowedChannel {
  my $event_type = shift;
  my $channel    = shift;
  my $rescode    = shift;

  my $retval = 0;

  printDebug("isAllowedChannel: got type:$event_type resCode:$rescode",2);

  my $channel_exists;
  if ( $event_type eq 'event_start' ) {
    if ( $rescode == 0 ) {
      $channel_exists = exists( $event_start_notify_on_hook_success{$channel} )
        || exists( $event_start_notify_on_hook_success{all} );
    }
    else {
      $channel_exists = exists( $event_start_notify_on_hook_fail{$channel} )
        || exists( $event_start_notify_on_hook_fail{all} );
    }
  }
  elsif ( $event_type eq 'event_end' ) {
    if ( $rescode == 0 ) {
      $channel_exists = exists( $event_end_notify_on_hook_success{$channel} )
        || exists( $event_end_notify_on_hook_success{all} );
    }
    else {
      $channel_exists = exists( $event_end_notify_on_hook_fail{$channel} )
        || exists( $event_end_notify_on_hook_fail{all} );
    }

  }
  else {
    printError("Invalid event_type:$event_type sent to isAllowedChannel()");
    $channel_exists = 0;
    return 0;
  }
  return $channel_exists;

}

# Compares connection rules (monList/interval). Returns 1 if event should be send to this connection,
# 0 if not.
sub shouldSendEventToConn {
  my $alarm  = shift;
  my $ac     = shift;
  my $retVal = 0;

  # Let's see if this connection is interested in this alarm
  my $monlist   = $ac->{monlist};
  my $intlist   = $ac->{intlist};
  my $last_sent = $ac->{last_sent};

  # Remember that escontrol settings overrides this.
  # At this stage, we are checking if we should send,
  # so only check if escontrol notify is forced. mute is
  # checked in sendEvent,
  if ($use_escontrol_interface) {
    my $id   = $alarm->{MonitorId};
    my $name = $alarm->{Name};
    if ( getNotificationStatusEsControl($id) == ESCONTROL_FORCE_NOTIFY ) {
      printDebug(
        "ESCONTROL: Notifications are force enabled for Monitor:$name($id), returning true",1
      );
      return 1;
    }

    if ( getNotificationStatusEsControl($id) == ESCONTROL_FORCE_MUTE ) {
      printDebug(
        "ESCONTROL: Notifications are muted for Monitor:$name($id), not sending",1
      );
      return 0;

    }

  }

  my $id     = getConnectionIdentity($ac);
  my $connId = $ac->{id};
  printDebug("Checking alarm rules for $id",1);

  if ( isInList( $monlist, $alarm->{MonitorId} ) ) {
    my $mint = getInterval( $intlist, $monlist, $alarm->{MonitorId} );
    my $elapsed;
    my $t = time();
    if ( $last_sent->{ $alarm->{MonitorId} } ) {
      $elapsed = time() - $last_sent->{ $alarm->{MonitorId} };
      if ( $elapsed >= $mint ) {
        printDebug( 'Monitor '
            . $alarm->{MonitorId}
            . " event: should send out as  $elapsed is >= interval of $mint" ,1);
        $retVal = 1;

      }
      else {

        printDebug( 'Monitor '
            . $alarm->{MonitorId}
            . " event: should NOT send this out as $elapsed is less than interval of $mint",1
        );
        $retVal = 0;
      }

    }
    else {

      # This means we have no record of sending any event to this monitor
      #$last_sent->{$_->{MonitorId}} = time();
      printDebug( 'Monitor '
          . $alarm->{MonitorId}
          . ' event: last time not found, so should send',1 );
      $retVal = 1;
    }
  }
  else    # monitorId not in list
  {
    printDebug( 'should NOT send alarm as Monitor '
        . $alarm->{MonitorId}
        . ' is excluded',1 );
    $retVal = 0;
  }

  return $retVal;
}

# If there are events reported in checkNewEvents, processAlarms is called to
# 1. Apply hooks if applicable
# 2. Send them out
# IMPORTANT: processAlarms is called as a forked child
# so remember not to manipulate data owned by the parent that needs to persist
# Use the parent<-child pipe if needed

#  @events will have the list of alarms we need to process and send out
# structure {Name => $name, MonitorId => $mid, EventId => $current_event, Cause=> $alarm_cause};

sub processNewAlarmsInFork {

  # This fork will stay alive till the event in question is completed
  my $newEvent       = shift;
  my $alarm          = $newEvent->{Alarm};
  my $monitor        = $newEvent->{MonitorObj};
  my $mid            = $alarm->{MonitorId};
  my $eid            = $alarm->{EventId};
  my $mname          = $alarm->{MonitorName};
  my $doneProcessing = 0;

  # will contain succ/fail of hook scripts, or 1 (fail) if not invoked
  my $hookResult      = 0;
  my $startHookResult = $hookResult;
  my $startHookString = '';

  my $endProcessed = 0;

  $prefix = "|----> FORK:$mname ($mid), eid:$eid";

  my $start_time = time();

  while ( !$doneProcessing ) {

    #print "FORK:".Dumper(\$alarm);
    my $now = time();
    if ( $now - $start_time > 3600 ) {
      printInfo('Thread alive for an hour, bailing...');

      $doneProcessing = 1;

    }

    # ---------- Event start processing ----------------------------------#
    # every alarm that comes here first starts with pending
    if ( $alarm->{Start}->{State} eq 'pending' ) {

      # is this monitor blocked from hooks in config?
      if ( $hook_skip_monitors{$mid} ) {
        printInfo("$mid is in hook skip list, not using hooks");
        $alarm->{Start}->{State} = 'ready';

        # lets treat this like a hook success so it
        # gets sent out
        $hookResult = 0;
      }
      else {    # not a blocked monitor

        if ( $event_start_hook && $use_hooks ) {

          # invoke hook start script
          my $cmd =
              $event_start_hook . ' '
            . $eid . ' '
            . $mid . ' "'
            . $alarm->{MonitorName} . '" "'
            . $alarm->{Start}->{Cause} . '"';

          if ($hook_pass_image_path) {
            my $event = new ZoneMinder::Event($eid);
            $cmd = $cmd . ' "' . $event->Path() . '"';
            printDebug( 'Adding event path:'
                . $event->Path()
                . ' to hook for image storage' ,2);

          }
          printDebug( 'Invoking hook on event start:' . $cmd ,1);

          if ( $cmd =~ /^(.*)$/ ) {
            $cmd = $1;
          }
          my $res = `$cmd`;
          chomp($res);
          my ( $resTxt, $resJsonString ) = parseDetectResults($res);
          $hookResult      = $? >> 8;
          $startHookResult = $hookResult;

          printDebug(
            "hook start returned with text:$resTxt json:$resJsonString exit:$hookResult",1
          );

          if ($event_start_hook_notify_userscript) {
            my $user_cmd =
              $event_start_hook_notify_userscript . ' '
            . $hookResult. ' '
            . $eid . ' '
            . $mid . ' '
            . '"'.$alarm->{MonitorName} .'" '
            . '"'.$resTxt.'" '
            . '"'.$resJsonString.'" ';


            if ($hook_pass_image_path) {
              my $event = new ZoneMinder::Event($eid);
              $user_cmd = $user_cmd . ' "' . $event->Path() . '"';
              printDebug( 'Adding event path:'
                  . $event->Path()
                  . ' to $user_cmd for image location' ,1);

            }

            if ( $user_cmd =~ /^(.*)$/ ) {
              $user_cmd = $1;
            }
            printDebug ("invoking user start notification script $user_cmd",1);
            my $user_res = `$user_cmd`;
          } # user notify script
          
          

          if ( $use_hook_description && $hookResult == 0 ) {

       # lets append it to any existing motion notes
       # note that this is in the fork. We are only passing hook text
       # to parent, so it can be appended to the full motion text on event close

            $alarm->{Start}->{Cause} =
              $resTxt . ' ' . $alarm->{Start}->{Cause};
            $alarm->{Start}->{DetectionJson} = decode_json($resJsonString);

            print WRITER 'active_event_update--TYPE--'
              . $mid
              . '--SPLIT--'
              . $eid
              . '--SPLIT--' . 'Start'
              . '--SPLIT--' . 'Cause'
              . '--SPLIT--'
              . $alarm->{Start}->{Cause}
              . '--JSON--'
              . $alarm->{Start}->{resJsonString} . "\n";

  # This updates the ZM DB with the detected description
  # we are writing resTxt not alarm cause which is only detection text
  # when we write to DB, we will add the latest notes, which may have more zones
            print WRITER 'event_description--TYPE--'
              . $mid
              . '--SPLIT--'
              . $eid
              . '--SPLIT--'
              . $resTxt . "\n";

            $startHookString = $resTxt;
          }    # use_hook_desc

        }

        # Coming here means we are not using start hooks
        else {    # treat it as a success if no hook to be used
          printInfo(
            'use hooks/start hook not being used, going to directly send out a notification if checks pass'
          );
          $hookResult = 0;
        }

        $alarm->{Start}->{State} = 'ready';

      }    # hook start script

      # end of State == pending
    }
    elsif ( $alarm->{Start}->{State} eq 'ready' ) {

      # temp wrapper object for now to keep to old interface
      # will eventually replace
      my $cause          = $alarm->{Start}->{Cause};
      my $detectJson     = $alarm->{Start}->{DetectionJson} || [];
      my $temp_alarm_obj = {
        Name          => $mname,
        MonitorId     => $mid,
        EventId       => $eid,
        Cause         => $cause,
        DetectionJson => $detectJson

      };

      if ( $use_api_push && $api_push_script ) {
        if ( isAllowedChannel( 'event_start', 'api', $hookResult )
          || !$event_start_hook
          || !$use_hooks )
        {
          printInfo('Sending push over API as it is allowed for event_start');

          my $api_cmd =
              $api_push_script . ' '
            . $eid . ' '
            . $mid . ' ' . ' "'
            . $temp_alarm_obj->{Name} . '" ' . ' "'
            . $temp_alarm_obj->{Cause} . '" '
            . " event_start";

          if ($hook_pass_image_path) {
            my $event = new ZoneMinder::Event($eid);
            $api_cmd = $api_cmd . ' "' . $event->Path() . '"';
            printDebug( 'Adding event path:'
                . $event->Path()
                . ' to api_cmd for image location' ,2);

          }

          printInfo("Executing API script command for event_start $api_cmd");
          if ( $api_cmd =~ /^(.*)$/ ) {
            $api_cmd = $1;
          }
          my $api_res = `$api_cmd`;
          printInfo("Returned from $api_cmd");
          chomp($api_res);
          my $api_retcode = $? >> 8;
          printDebug("API push script returned : $api_retcode",1);

        }
        else {
          printInfo(
            'Not sending push over API as it is not allowed for event_start');
        }

      }
      printDebug('Matching alarm to connection rules...',1);
      my ($serv) = @_;
      foreach (@active_connections) {

        if ( shouldSendEventToConn( $temp_alarm_obj, $_ ) ) {
          printDebug(
            'shouldSendEventToConn returned true, so calling sendEvent',1);
          sendEvent( $temp_alarm_obj, $_, 'event_start', $hookResult );

        }
      }    # foreach active_connections
      $alarm->{Start}->{State} = 'done';
    }

    # ---------- Event End processing ----------------------------------#
    elsif ( $alarm->{End}->{State} eq 'pending' ) {

      # this means we need to invoke a hook
      if ( $alarm->{Start}->{State} ne 'done' ) {
        printDebug(
          'Not yet sending out end notification as start hook/notify is not done',2
        );

        #$hookResult = 0; # why ? forgot.
      }
      else {    # start processing over, so end can be processed

        my $notes = getNotesFromEventDB($eid);
        if ($startHookString) {
          if ( index( $notes, 'detected:' ) == -1 ) {
            printDebug(
              "ZM overwrote detection DB, current notes: [$notes], adding detection notes back into DB [$startHookString]",1
            );
            # This will be prefixed, so no need to add old notes back
            updateEventinZmDB( $eid, $startHookString );
          }
          else {
            printDebug("DB Event notes contain detection text, all good",2);
          }
        }

        if ( $event_end_hook && $use_hooks ) {

          # invoke end hook script
          my $cmd =
              $event_end_hook . ' '
            . $eid . ' '
            . $mid . ' "'
            . $alarm->{MonitorName} . '" "'
            . $notes . '"';

          if ($hook_pass_image_path) {
            my $event = new ZoneMinder::Event($eid);
            $cmd = $cmd . ' "' . $event->Path() . '"';
            printDebug( 'Adding event path:'
                . $event->Path()
                . ' to hook for image storage',2 );

          }
          printDebug( 'Invoking hook on event end:' . $cmd ,1);
          if ( $cmd =~ /^(.*)$/ ) {
            $cmd = $1;
          }
          my $res = `$cmd`;
          chomp($res);
          my ( $resTxt, $resJsonString ) = parseDetectResults($res);
          $hookResult = $? >> 8;

          $alarm->{End}->{State} = 'ready';
          printDebug(
            "hook end returned with text:$resTxt  json:$resJsonString exit:$hookResult",1
          );

          #tbd  - was this a typo? Why ->{Cause}?
          # kept it here for now
          #$alarm->{Cause} = $resTxt . ' ' . $alarm->{Cause};
          #$alarm->{End}->{Cause} = $resTxt;

          #I think this is what we need

          #$alarm->{End}->{Cause}         = $resTxt . ' ' . $alarm->{Cause};
          $alarm->{End}->{Cause}         = $resTxt;
          $alarm->{End}->{DetectionJson} = decode_json($resJsonString);



          if ($event_end_hook_notify_userscript) {
            my $user_cmd =
              $event_end_hook_notify_userscript . ' '
            . $hookResult. ' '
            . $eid . ' '
            . $mid . ' '
            . '"'.$alarm->{MonitorName} .'" '
            . '"'.$resTxt.'" '
            . '"'.$resJsonString.'" ';

            if ($hook_pass_image_path) {
              my $event = new ZoneMinder::Event($eid);
              $user_cmd = $user_cmd . ' "' . $event->Path() . '"';
              printDebug( 'Adding event path:'
                  . $event->Path()
                  . ' to $user_cmd for image location' ,2);

            }

            if ( $user_cmd =~ /^(.*)$/ ) {
              $user_cmd = $1;
            }
            printDebug ("invoking user end notification script $user_cmd",1);
            my $user_res = `$user_cmd`;
          } # user notify script

        }
        else {
          # treat it as a success if no hook to be used
          printInfo(
            'end hooks/use hooks not being used, going to directly send out a notification if checks pass'
          );
          $hookResult = 0;
        }

        $alarm->{End}->{State} = 'ready';

      }    # hook end script

      # end of State == pending
    }
    elsif ( $alarm->{End}->{State} eq 'ready' ) {

 # note that this end_notify_if_start is default yes, even if you comment it out
 # so if you disable all hooks params, you won't get end notifs
      if ( $event_end_notify_if_start_success && $startHookResult != 0 ) {
        printInfo(
          'Not sending event end alarm, as we did not send a start alarm for this, or start hook processing failed'
        );
      }
      else {

        my $cause          = $alarm->{End}->{Cause};
        my $detectJson     = $alarm->{End}->{DetectionJson} || [];
        my $temp_alarm_obj = {
          Name          => $mname,
          MonitorId     => $mid,
          EventId       => $eid,
          Cause         => $cause,
          DetectionJson => $detectJson
        };

        if ( $use_api_push && $api_push_script ) {

          if ($send_event_end_notification) {

            if ( isAllowedChannel( 'event_end', 'api', $hookResult )
              || !$event_end_hook
              || !$use_hooks )
            {
              printDebug('Sending push over API as it is allowed for event_end',1);

              my $api_cmd =
                  $api_push_script . ' '
                . $eid . ' '
                . $mid . ' ' . ' "'
                . $temp_alarm_obj->{Name} . '" ' . ' "'
                . $temp_alarm_obj->{Cause} . '" '
                . " event_end";

              if ($hook_pass_image_path) {
                my $event = new ZoneMinder::Event($eid);
                $api_cmd = $api_cmd . ' "' . $event->Path() . '"';
                printDebug( 'Adding event path:'
                    . $event->Path()
                    . ' to api_cmd for image location',2 );

              }

              printInfo("Executing API script command for event_end $api_cmd");

              if ( $api_cmd =~ /^(.*)$/ ) {
                $api_cmd = $1;
              }
              my $res = `$api_cmd`;
              printDebug("returned from api cmd for event_end",2);
              chomp($res);
              my $retcode = $? >> 8;
              printDebug("API push script returned (event_end) : $retcode",1);

            }
            else {
              printDebug(
                'Not sending push over API as it is not allowed for event_start',1
              );
            }

          }
          else {
            printDebug(
              'Not sending event_end push over API as send_event_end_notification is no',1
            );
          }

        }

        # end will never be ready before start is ready
        # this means we need to notify
        printDebug('Matching alarm to connection rules...',1);

        my ($serv) = @_;
        foreach (@active_connections) {

           if(isInList($_->{monlist}, $temp_alarm_obj->{MonitorId})) {
             sendEvent( $temp_alarm_obj, $_, 'event_end', $hookResult );
           } else {
            printDebug ("Skipping FCM notification as Monitor:".$temp_alarm_obj->{Name}."(".$temp_alarm_obj->{MonitorId}.") is excluded from zmNinja monitor list",1);
          }
          
        }    # foreach active_connections
      }

      $alarm->{End}->{State} = 'done';

      #$active_events{$mid}{$eid}{'start'}->{State} = 'done';
    }    # end state = ready
    elsif ( $alarm->{End}->{State} eq 'done' ) {

      # The end of this event lifecycle. Both start and end handled
      # as needed
      $doneProcessing = 1;
    }

    if ( !zmMemVerify($monitor) ) {

      printError('SHM failed, re-validating it');
      loadMonitor($monitor);

    }
    else {
      my $state   = zmGetMonitorState($monitor);
      my $shm_eid = zmGetLastEvent($monitor);

      if ( ( $state == STATE_IDLE || $state == STATE_TAPE || $shm_eid != $eid )
        && !$endProcessed )

        # The alarm has ended
      {
        printDebug("For $mid ($mname), SHM says: state=$state, eid=$shm_eid",3);
        printInfo("Event $eid for Monitor $mid has finished");
        $endProcessed = 1;

        $alarm->{End} = {
          State => 'pending',
          Time  => time(),
          Cause => getNotesFromEventDB($eid)
        };

        printDebug( 'Event end object is: state=>'
            . $alarm->{End}->{State}
            . ' with cause=>'
            . $alarm->{End}->{Cause} ,3);
      }
    }
    sleep(2);
  }

  printDebug('exiting',1);
  print WRITER 'active_event_delete--TYPE--' . $mid . '--SPLIT--' . $eid . "\n";
  close(WRITER);

}    # sub processNewAlarms

#restarts ES
sub restartES {

  $wss->shutdown();
  if ($zmdc_active) {
    printInfo('Exiting, zmdc will restart me');
    exit 0;
  }
  else {
    printDebug('Self exec-ing as zmdc is not tracking me');

    # untaint via reg-exp
    if ( $0 =~ /^(.*)$/ ) {
      my $f = $1;
      printInfo("restarting $f");
      exec($f);
    }
  }
}

# This is really the main module
# It opens a WSS socket and keeps listening
sub initSocketServer {
  checkNewEvents();
  my $ssl_server;
  if ($ssl_enabled) {
    printDebug('About to start listening to socket',2);
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
      );
    };
    if ($@) {
      printError("Failed starting server: $@");
      exit(-1);
    }
    printInfo('Secure WS(WSS) is enabled...');
  }
  else {
    printInfo('Secure WS is disabled...');
  }
  printInfo( 'Web Socket Event Server listening on port ' . $port );

  $wss = Net::WebSocket::Server->new(
    listen => $ssl_enabled ? $ssl_server : $port,
    tick_period => $event_check_interval,
    on_tick     => sub {
      printDebug('---------->Tick START<--------------',2);
      if ( $restart_interval
        && ( ( time() - $es_start_time ) > $restart_interval ) )
      {
        printInfo(
          "Time to restart ES as it has been running more that $restart_interval seconds"
        );
        restartES();

      }

      # keep the MQTT connection from timing out
      if ( $use_mqtt
        && ( ( time() - $mqtt_last_tick_time ) > $mqtt_tick_interval ) )
      {
        printDebug(
          'MQTT tick interval (' . $mqtt_tick_interval . ' sec) elapsed.',2 );
        $mqtt_last_tick_time = time();
        foreach (@active_connections) {
          $_->{mqtt_conn}->tick(0) if ( $_->{type} == MQTT );
        }
      }

      checkConnection();
      processJobs();

      printDebug("There are $child_forks active child forks...",2);
      my (@newEvents) = checkNewEvents();

      #print Dumper(\@newEvents);

      printDebug( 'There are ' . scalar @newEvents . ' new Events to process',2 );
      foreach (@newEvents) {
        $child_forks++;
        my $pid = fork;
        if ( !defined $pid ) {
          die "Cannot fork: $!";
        }
        elsif ( $pid == 0 ) {

          # do this to get a proper return value
          # $SIG{CHLD} = undef;
          local $SIG{'CHLD'} = 'DEFAULT';

          #$wss->shutdown();
          close(READER);
          $dbh = zmDbConnect(1);
          logReinit();

          printDebug(
            "Forked process:$$ to handle alarm eid:" . $_->{Alarm}->{EventId},1 );

# send it the list of current events to handle bcause checkNewEvents() will clean it
          processNewAlarmsInFork($_);
          printDebug("Ending process:$$ to handle alarms",1);

          exit 0;

        }

      }

      printDebug('---------->Tick END<--------------',2);
    },

    # called when a new connection comes in
    on_connect => sub {
      my ( $serv, $conn ) = @_;
      printDebug('---------->onConnect START<--------------',2);
      my ($len) = scalar @active_connections;
      printDebug( 'got a websocket connection from '
          . $conn->ip() . ' ('
          . $len
          . ') active connections' ,1);

      #print Dumper($conn);
      $conn->on(
        utf8 => sub {
          printDebug('---------->onConnect msg START<--------------',2);
          my ( $conn, $msg ) = @_;
          my $dmsg = $msg;
          $dmsg =~ s/\"password\":\"(.*?)\"/"password":\*\*\*/;
          printDebug("Raw incoming message: $dmsg",3);
          processIncomingMessage( $conn, $msg );
          printDebug('---------->onConnect msg STOP<--------------',2);
        },
        handshake => sub {
          my ( $conn, $handshake ) = @_;
          printDebug('---------->onConnect:handshake START<--------------',2);
          my $fields = '';

          # Stuff in more headers you want here over time
          if ( $handshake->req->fields ) {
            my $f = $handshake->req->fields;

            #print Dumper($f);
            $fields = $fields . ' X-Forwarded-For:' . $f->{'x-forwarded-for'}
              if $f->{'x-forwarded-for'};

            #$fields = $fields." host:".$f->{"host"} if $f->{"host"};

          }

          #print Dumper($handshake);
          my $id           = gettimeofday;
          my $connect_time = time();
          push @active_connections,
            {
            type         => WEB,
            conn         => $conn,
            id           => $id,
            state        => PENDING_AUTH,
            time         => $connect_time,
            monlist      => '',
            intlist      => '',
            last_sent    => {},
            platform     => 'websocket',
            pushstate    => '',
            extra_fields => $fields,
            badge        => 0,
            category     => 'normal',
            };
          printDebug( 'Websockets: New Connection Handshake requested from '
              . $conn->ip() . ':'
              . $conn->port()
              . getConnFields($conn)
              . ' state=pending auth, id='
              . $id,1 );

          printDebug('---------->onConnect:handshake END<--------------',2);
        },
        disconnect => sub {
          my ( $conn, $code, $reason ) = @_;
          printDebug('---------->onConnect:disconnect START<--------------',2);
          printDebug( 'Websocket remotely disconnected from '
              . $conn->ip()
              . getConnFields($conn),1 );
          foreach (@active_connections) {
            if ( ( exists $_->{conn} )
              && ( $_->{conn}->ip() eq $conn->ip() )
              && ( $_->{conn}->port() eq $conn->port() ) )
            {

              # mark this for deletion only if device token
              # not present
              if ( $_->{token} eq '' ) {
                $_->{state} = PENDING_DELETE;
                printDebug( 'Marking '
                    . $conn->ip()
                    . getConnFields($conn)
                    . " for deletion as websocket closed remotely\n" ,1);
              }
              else {

                printDebug( 'Invaliding websocket, but NOT Marking '
                    . $conn->ip()
                    . getConnFields($conn)
                    . ' for deletion as token '
                    . $_->{token}
                    . " active\n",1 );
                $_->{state} = INVALID_CONNECTION;
              }
            }

          }
          printDebug('---------->onConnect:disconnect END<--------------',2);
        },
      );

      printDebug('---------->onConnect STOP<--------------',2);
    }
  );

  $wss->start();
}
