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

# ---- ZoneMinder::Tag ----
{
    package ZoneMinder::Tag;
    $INC{'ZoneMinder/Tag.pm'} = __FILE__;
    my @_spy_find_one;
    my @_spy_save;
    my $_next_find_one;
    sub _reset_spy   { @_spy_find_one = (); @_spy_save = (); $_next_find_one = undef; }
    sub _spy_find_one_calls { @_spy_find_one }
    sub _spy_save_calls     { @_spy_save }
    sub _set_next_find_one  { $_next_find_one = $_[1] }
    sub find_one {
        shift;   # class
        push @_spy_find_one, [@_];
        return $_next_find_one;
    }
    sub new {
        my $class = shift;
        return bless { Id => int(rand(9999)) + 1 }, $class;
    }
    sub save {
        my ($self, $data) = @_;
        push @_spy_save, { self => $self, data => $data };
        @{$self}{keys %$data} = values %$data if $data;
    }
    sub import { 1 }
}

# ---- ZoneMinder::Event_Tag ----
{
    package ZoneMinder::Event_Tag;
    $INC{'ZoneMinder/Event_Tag.pm'} = __FILE__;
    my @_spy_save;
    sub _reset_spy   { @_spy_save = (); }
    sub _spy_save_calls { @_spy_save }
    sub save {
        my ($self, $data) = @_;
        push @_spy_save, { self => $self, data => $data };
        @{$self}{keys %$data} = values %$data if $data;
    }
    sub import { 1 }
}

# ---- ZoneMinder::User ----
{
    package ZoneMinder::User;
    $INC{'ZoneMinder/User.pm'} = __FILE__;
    my $_next_find_one;
    sub _set_next_find_one { $_next_find_one = $_[1] }
    sub _reset             { $_next_find_one = undef }
    sub find_one {
        shift;   # class
        return $_next_find_one;
    }
    sub import { 1 }
}

# ---- ZM_VERSION in ZoneMinder package ----
# DB.pm does `use ZoneMinder` and then calls ZM_VERSION as a bareword.
# We define it as a regular sub (no prototype) so Perl won't inline it,
# allowing tests to override $ZoneMinder::_zm_version with `local`.
{
    package ZoneMinder;
    our $_zm_version = '1.38.0';
    sub ZM_VERSION { $_zm_version }  ## no prototype -> not inlined
    no warnings 'redefine';
    sub import {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::ZM_VERSION"} = \&ZM_VERSION;
    }
}

# ---- main:: logging stubs ----
package main;
our $is_timepiece = 1;   # Rules.pm checks this
our @active_connections = ();
our %monitors = ();
our $es_terminate = 0;
our $config_file;
our $config_file_present;
our %ssl_push_opts = ();
our $notId = 0;
our %fcm_tokens_map = ();

sub Debug   { }
sub Info    { }
sub Warning { }
sub Error   { }
sub Fatal   { die "FATAL: $_[1]\n" if @_ > 1; die "FATAL\n" }
sub try_use { 0 }

# SHM stubs used by HookProcessor
sub zmMemVerify       { 1 }
sub loadMonitor       { 1 }
sub loadMonitors      { 1 }
sub zmGetMonitorState { 0 }
sub zmGetLastEvent    { 0 }
sub STATE_IDLE        { 0 }
sub STATE_TAPE        { 1 }

1;
