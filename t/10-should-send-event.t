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

# Stub out the heavy dependencies before loading HookProcessor.
# Use a package var so the closure in BEGIN can reference it.
our $escontrol_return;

BEGIN {
    $escontrol_return = 0;  # ESCONTROL_DEFAULT_NOTIFY = 0

    for my $pkg (qw(
        ZmEventNotification::FCM
        ZmEventNotification::MQTT
        ZmEventNotification::DB
        ZmEventNotification::WebSocketHandler
    )) {
        (my $file = $pkg) =~ s{::}{/}g;
        $INC{"$file.pm"} = 1;
    }
    no strict 'refs';
    *{'ZmEventNotification::FCM::sendOverFCM'} = sub { };
    *{'ZmEventNotification::FCM::import'} = sub {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::sendOverFCM"} = \&ZmEventNotification::FCM::sendOverFCM;
    };
    *{'ZmEventNotification::MQTT::sendOverMQTTBroker'} = sub { };
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
    *{'ZmEventNotification::WebSocketHandler::getNotificationStatusEsControl'} = sub { $escontrol_return };
    *{'ZmEventNotification::WebSocketHandler::import'} = sub {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::getNotificationStatusEsControl"} = \&ZmEventNotification::WebSocketHandler::getNotificationStatusEsControl;
    };
}

use_ok('ZmEventNotification::HookProcessor');
ZmEventNotification::HookProcessor->import(':all');

# Disable escontrol by default
$escontrol_config{enabled} = 0;

my $alarm = { MonitorId => '1', Name => 'Front' };

# ===== Monitor in monlist, no prior send -> 1 =====
{
    my $ac = {
        monlist   => '1,2,3',
        intlist   => '0,0,0',
        last_sent => {},
        type      => FCM,
        token     => 'tok_test1_1234567890',
        id        => 1,
    };
    is(shouldSendEventToConn($alarm, $ac), 1, 'monitor in list, no prior send -> 1');
}

# ===== Monitor NOT in monlist -> 0 =====
{
    my $ac = {
        monlist   => '2,3',
        intlist   => '0,0',
        last_sent => {},
        type      => FCM,
        token     => 'tok_test2_1234567890',
        id        => 2,
    };
    is(shouldSendEventToConn($alarm, $ac), 0, 'monitor NOT in monlist -> 0');
}

# ===== Monitor in list, within interval -> 0 =====
{
    my $ac = {
        monlist   => '1,2',
        intlist   => '600,0',
        last_sent => { '1' => time() - 10 },  # 10 secs ago, interval is 600
        type      => FCM,
        token     => 'tok_test3_1234567890',
        id        => 3,
    };
    is(shouldSendEventToConn($alarm, $ac), 0, 'within interval -> 0');
}

# ===== Monitor in list, past interval -> 1 =====
{
    my $ac = {
        monlist   => '1,2',
        intlist   => '5,0',
        last_sent => { '1' => time() - 100 },  # 100 secs ago, interval is 5
        type      => FCM,
        token     => 'tok_test4_1234567890',
        id        => 4,
    };
    is(shouldSendEventToConn($alarm, $ac), 1, 'past interval -> 1');
}

# ===== Empty monlist (all monitors) -> 1 =====
{
    my $ac = {
        monlist   => '',
        intlist   => '',
        last_sent => {},
        type      => FCM,
        token     => 'tok_test5_1234567890',
        id        => 5,
    };
    is(shouldSendEventToConn($alarm, $ac), 1, 'empty monlist -> 1');
}

# ===== monlist=-1 (all monitors) -> 1 =====
{
    my $ac = {
        monlist   => '-1',
        intlist   => '',
        last_sent => {},
        type      => FCM,
        token     => 'tok_test6_1234567890',
        id        => 6,
    };
    is(shouldSendEventToConn($alarm, $ac), 1, 'monlist=-1 -> 1');
}

# ===== escontrol FORCE_NOTIFY -> 1 regardless =====
{
    local $escontrol_config{enabled} = 1;
    $escontrol_return = ESCONTROL_FORCE_NOTIFY;
    my $ac = {
        monlist   => '99',          # monitor 1 not in list
        intlist   => '0',
        last_sent => {},
        type      => FCM,
        token     => 'tok_test7_1234567890',
        id        => 7,
    };
    is(shouldSendEventToConn($alarm, $ac), 1, 'FORCE_NOTIFY -> 1 regardless');
    $escontrol_return = ESCONTROL_DEFAULT_NOTIFY;
}

# ===== escontrol FORCE_MUTE -> 0 regardless =====
{
    local $escontrol_config{enabled} = 1;
    $escontrol_return = ESCONTROL_FORCE_MUTE;
    my $ac = {
        monlist   => '1,2',
        intlist   => '0,0',
        last_sent => {},
        type      => FCM,
        token     => 'tok_test8_1234567890',
        id        => 8,
    };
    is(shouldSendEventToConn($alarm, $ac), 0, 'FORCE_MUTE -> 0 regardless');
    $escontrol_return = ESCONTROL_DEFAULT_NOTIFY;
}

# ===== escontrol DEFAULT -> falls through to normal logic =====
{
    local $escontrol_config{enabled} = 1;
    $escontrol_return = ESCONTROL_DEFAULT_NOTIFY;
    my $ac = {
        monlist   => '1,2',
        intlist   => '0,0',
        last_sent => {},
        type      => FCM,
        token     => 'tok_test9_1234567890',
        id        => 9,
    };
    is(shouldSendEventToConn($alarm, $ac), 1, 'DEFAULT -> normal logic (in list, no prior send) -> 1');
}

# ===== Multiple monitors, correct interval selected =====
{
    my $alarm5 = { MonitorId => '5', Name => 'Side' };
    my $ac = {
        monlist   => '1,5,10',
        intlist   => '60,120,300',
        last_sent => { '5' => time() - 60 },  # 60 secs ago, interval for mid=5 is 120
        type      => FCM,
        token     => 'tok_test10_1234567890',
        id        => 10,
    };
    is(shouldSendEventToConn($alarm5, $ac), 0, 'mid=5 interval=120, elapsed=60 -> 0');

    $ac->{last_sent} = { '5' => time() - 200 };  # 200 secs ago > 120 interval
    is(shouldSendEventToConn($alarm5, $ac), 1, 'mid=5 interval=120, elapsed=200 -> 1');
}

done_testing();
