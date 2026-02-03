# StubZM.pm -- provide fake ZoneMinder packages so the ES modules
# can be loaded without a real ZM installation.
package StubZM;
use strict;
use warnings;

# ---- ZoneMinder top-level package ----
{
    package ZoneMinder;
    our $VERSION = '0.00_stub';
    $INC{'ZoneMinder.pm'} = __FILE__;
    sub import { 1 }
}

# ---- ZoneMinder::Config ----
{
    package ZoneMinder::Config;
    our $ZM_OPT_USE_AUTH = 1;
    $INC{'ZoneMinder/Config.pm'} = __FILE__;
    sub import { 1 }
}

# ---- ZoneMinder::Logger ----
{
    package ZoneMinder::Logger;
    $INC{'ZoneMinder/Logger.pm'} = __FILE__;
    sub import { 1 }
}

# ---- ZoneMinder::Monitor ----
{
    package ZoneMinder::Monitor;
    $INC{'ZoneMinder/Monitor.pm'} = __FILE__;
    sub new  { bless {}, shift }
    sub find { () }
    sub import { 1 }
}

# ---- ZoneMinder::Event ----
{
    package ZoneMinder::Event;
    $INC{'ZoneMinder/Event.pm'} = __FILE__;
    sub new  { bless { id => $_[1] }, $_[0] }
    sub Path { '/tmp/fake_event_path' }
    sub import { 1 }
}

# ---- main:: logging stubs ----
package main;
our $is_timepiece = 1;   # Rules.pm checks this
our @active_connections = ();
our %monitors = ();
our $es_terminate = 0;
our $config_file;
our $config_file_present;

sub Debug   { }
sub Info    { }
sub Warning { }
sub Error   { }
sub Fatal   { die "FATAL: $_[1]\n" if @_ > 1; die "FATAL\n" }

# SHM stubs used by HookProcessor
sub zmMemVerify       { 1 }
sub loadMonitor       { 1 }
sub loadMonitors      { 1 }
sub zmGetMonitorState { 0 }
sub zmGetLastEvent    { 0 }
sub STATE_IDLE        { 0 }
sub STATE_TAPE        { 1 }

1;
