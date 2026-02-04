#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../";
use lib "$FindBin::Bin/lib";

use Test::More;
use YAML::XS;
use File::Spec;

require StubZM;

use ZmEventNotification::Config qw(:all);
use ZmEventNotification::Constants qw(:all);

# Load config
my $fixtures = File::Spec->catdir($FindBin::Bin, 'fixtures');
my $cfg = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_es.yml'));
my $sec = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_secrets.yml'));
$ZmEventNotification::Config::secrets = $sec;
loadEsConfigSettings($cfg);

# Spy counters (our so BEGIN block can see them)
our %spy;

BEGIN {
    %spy = (fcm => 0, ws => 0, mqtt => 0);
    for my $pkg (qw(
        ZmEventNotification::FCM
        ZmEventNotification::MQTT
        ZmEventNotification::DB
        ZmEventNotification::WebSocketHandler
    )) {
        (my $file = $pkg) =~ s{::}{/}g;
        $INC{"$file.pm"} = 1;
    }
    # Provide stubs in source packages
    no strict 'refs';
    *{'ZmEventNotification::FCM::sendOverFCM'} = sub { $spy{fcm}++ };
    *{'ZmEventNotification::FCM::import'} = sub {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::sendOverFCM"} = \&ZmEventNotification::FCM::sendOverFCM;
    };
    *{'ZmEventNotification::MQTT::sendOverMQTTBroker'} = sub { $spy{mqtt}++ };
    *{'ZmEventNotification::MQTT::import'} = sub {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::sendOverMQTTBroker"} = \&ZmEventNotification::MQTT::sendOverMQTTBroker;
    };
    *{'ZmEventNotification::DB::updateEventinZmDB'} = sub { };
    *{'ZmEventNotification::DB::getNotesFromEventDB'} = sub { '' };
    *{'ZmEventNotification::DB::tagEventObjects'} = sub { };
    *{'ZmEventNotification::DB::import'} = sub {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::updateEventinZmDB"} = \&ZmEventNotification::DB::updateEventinZmDB;
        *{"${caller}::getNotesFromEventDB"} = \&ZmEventNotification::DB::getNotesFromEventDB;
        *{"${caller}::tagEventObjects"} = \&ZmEventNotification::DB::tagEventObjects;
    };
    *{'ZmEventNotification::WebSocketHandler::getNotificationStatusEsControl'} = sub { 0 };
    *{'ZmEventNotification::WebSocketHandler::import'} = sub {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::getNotificationStatusEsControl"} = \&ZmEventNotification::WebSocketHandler::getNotificationStatusEsControl;
    };
}

use_ok('ZmEventNotification::HookProcessor');
ZmEventNotification::HookProcessor->import(':all');

# Set up WRITER
my $pipe_output = '';
open(my $writer_fh, '>', \$pipe_output) or die "Cannot open scalar ref: $!";
$writer_fh->autoflush(1);
*main::WRITER = *$writer_fh;

# Mock conn
{
    package MockConn;
    sub new  { bless {}, shift }
    sub ip   { '10.0.0.1' }
    sub port { 9000 }
}

my $alarm = {
    MonitorId     => '1',
    Name          => 'TestMon',
    EventId       => '100',
    Cause         => 'detected:person',
    DetectionJson => [],
    RulesObject   => {},
};

# Configure hooks enabled + channels to test routing
$hooks_config{enabled} = 1;
$hooks_config{event_start_hook} = '/usr/bin/detect';
$hooks_config{event_end_hook} = '/usr/bin/detect_end';
$hooks_config{event_start_notify_on_hook_success} = 'all';
$hooks_config{event_start_notify_on_hook_fail} = 'none';
$hooks_config{event_end_notify_on_hook_success} = 'fcm,web';
$hooks_config{event_end_notify_on_hook_fail} = 'none';

# ===== FCM: sent when type=FCM, pushstate=enabled, state=VALID, channel allowed =====
{
    %spy = (fcm => 0, ws => 0, mqtt => 0);
    $pipe_output = '';
    my $ac = {
        type      => FCM,
        pushstate => 'enabled',
        state     => VALID_CONNECTION,
        id        => 1,
        token     => 'tok_fcm_1234567890',
    };
    sendEvent($alarm, $ac, 'event_start', 0);
    is($spy{fcm}, 1, 'FCM: sent on event_start, success');
}

# ===== FCM: NOT sent when pushstate=disabled =====
{
    %spy = (fcm => 0, ws => 0, mqtt => 0);
    $pipe_output = '';
    my $ac = {
        type      => FCM,
        pushstate => 'disabled',
        state     => VALID_CONNECTION,
        id        => 2,
        token     => 'tok_fcm2_1234567890',
    };
    sendEvent($alarm, $ac, 'event_start', 0);
    is($spy{fcm}, 0, 'FCM: NOT sent when pushstate=disabled');
}

# ===== FCM: NOT sent when state=PENDING_AUTH =====
{
    %spy = (fcm => 0, ws => 0, mqtt => 0);
    $pipe_output = '';
    my $ac = {
        type      => FCM,
        pushstate => 'enabled',
        state     => PENDING_AUTH,
        id        => 3,
        token     => 'tok_fcm3_1234567890',
    };
    sendEvent($alarm, $ac, 'event_start', 0);
    is($spy{fcm}, 0, 'FCM: NOT sent when state=PENDING_AUTH');
}

# ===== FCM: NOT sent when state=PENDING_DELETE =====
{
    %spy = (fcm => 0, ws => 0, mqtt => 0);
    $pipe_output = '';
    my $ac = {
        type      => FCM,
        pushstate => 'enabled',
        state     => PENDING_DELETE,
        id        => 4,
        token     => 'tok_fcm4_1234567890',
    };
    sendEvent($alarm, $ac, 'event_start', 0);
    is($spy{fcm}, 0, 'FCM: NOT sent when state=PENDING_DELETE');
}

# ===== FCM: NOT sent when channel blocked (event_start fail, none) =====
{
    %spy = (fcm => 0, ws => 0, mqtt => 0);
    $pipe_output = '';
    my $ac = {
        type      => FCM,
        pushstate => 'enabled',
        state     => VALID_CONNECTION,
        id        => 5,
        token     => 'tok_fcm5_1234567890',
    };
    sendEvent($alarm, $ac, 'event_start', 1);  # resCode=1 -> fail channel
    is($spy{fcm}, 0, 'FCM: NOT sent when channel blocked (hook fail)');
}

# ===== WEB: sent when type=WEB, state=VALID, conn exists, channel allowed =====
{
    %spy = (fcm => 0, ws => 0, mqtt => 0);
    $pipe_output = '';
    my $ac = {
        type  => WEB,
        state => VALID_CONNECTION,
        id    => 10,
        conn  => MockConn->new(),
    };
    sendEvent($alarm, $ac, 'event_start', 0);
    # WebSocket sends via WRITER pipe, check pipe has message
    like($pipe_output, qr/message--TYPE--10--SPLIT--/, 'WEB: message sent via pipe');
}

# ===== WEB: NOT sent when no conn object =====
{
    %spy = (fcm => 0, ws => 0, mqtt => 0);
    $pipe_output = '';
    my $ac = {
        type  => WEB,
        state => VALID_CONNECTION,
        id    => 11,
        # no conn key
    };
    sendEvent($alarm, $ac, 'event_start', 0);
    # Should only have timestamp line, no message line
    unlike($pipe_output, qr/message--TYPE--11--SPLIT--/, 'WEB: NOT sent when no conn');
}

# ===== WEB: NOT sent when channel blocked =====
{
    %spy = (fcm => 0, ws => 0, mqtt => 0);
    $pipe_output = '';
    my $ac = {
        type  => WEB,
        state => VALID_CONNECTION,
        id    => 12,
        conn  => MockConn->new(),
    };
    sendEvent($alarm, $ac, 'event_start', 1);  # fail channel = none
    unlike($pipe_output, qr/message--TYPE--12--SPLIT--/, 'WEB: NOT sent when channel blocked');
}

# ===== MQTT: sent when type=MQTT, channel allowed =====
{
    %spy = (fcm => 0, ws => 0, mqtt => 0);
    $pipe_output = '';
    my $ac = {
        type => MQTT,
        id   => 20,
    };
    sendEvent($alarm, $ac, 'event_start', 0);
    is($spy{mqtt}, 1, 'MQTT: sent on event_start, success');
}

# ===== MQTT: NOT sent when channel blocked =====
{
    %spy = (fcm => 0, ws => 0, mqtt => 0);
    $pipe_output = '';
    my $ac = {
        type => MQTT,
        id   => 21,
    };
    sendEvent($alarm, $ac, 'event_start', 1);  # fail channel = none
    is($spy{mqtt}, 0, 'MQTT: NOT sent when channel blocked');
}

# ===== send_event_end_notification=no blocks all event_end sends =====
{
    %spy = (fcm => 0, ws => 0, mqtt => 0);
    $pipe_output = '';
    local $notify_config{send_event_end_notification} = 0;
    my $ac = {
        type      => FCM,
        pushstate => 'enabled',
        state     => VALID_CONNECTION,
        id        => 30,
        token     => 'tok_end_block_1234567890',
    };
    sendEvent($alarm, $ac, 'event_end', 0);
    is($spy{fcm}, 0, 'event_end blocked when send_event_end_notification=no');
    # No timestamp written either since function returns early
    unlike($pipe_output, qr/timestamp/, 'no timestamp when event_end blocked');
}

# ===== send_event_start_notification=no blocks all event_start sends =====
{
    %spy = (fcm => 0, ws => 0, mqtt => 0);
    $pipe_output = '';
    local $notify_config{send_event_start_notification} = 0;
    my $ac = {
        type      => FCM,
        pushstate => 'enabled',
        state     => VALID_CONNECTION,
        id        => 31,
        token     => 'tok_start_block_1234567890',
    };
    sendEvent($alarm, $ac, 'event_start', 0);
    is($spy{fcm}, 0, 'event_start blocked when send_event_start_notification=no');
}

# ===== timestamp line always written to WRITER =====
{
    $pipe_output = '';
    my $ac = {
        type      => FCM,
        pushstate => 'enabled',
        state     => VALID_CONNECTION,
        id        => 40,
        token     => 'tok_ts_test_1234567890',
    };
    sendEvent($alarm, $ac, 'event_start', 0);
    like($pipe_output, qr/timestamp--TYPE--40--SPLIT--1--SPLIT--/, 'timestamp line written with mid');
}

done_testing();
