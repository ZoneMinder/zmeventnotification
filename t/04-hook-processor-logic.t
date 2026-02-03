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

# Load config so hooks_config is populated
my $fixtures = File::Spec->catdir($FindBin::Bin, 'fixtures');
my $cfg = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_es.yml'));
my $sec = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_secrets.yml'));
$ZmEventNotification::Config::secrets = $sec;
loadEsConfigSettings($cfg);

# We can't fully load HookProcessor because it pulls in FCM, MQTT, etc.
# Instead, test isAllowedChannel directly by loading just that function.
# HookProcessor exports isAllowedChannel, so we eval-load it with stubs.

# Stub out the heavy dependencies
for my $pkg (qw(
    ZmEventNotification::FCM
    ZmEventNotification::MQTT
    ZmEventNotification::DB
    ZmEventNotification::WebSocketHandler
)) {
    (my $file = $pkg) =~ s{::}{/}g;
    $INC{"$file.pm"} = 1;
    no strict 'refs';
    *{"${pkg}::import"} = sub { 1 };
    # Provide dummy exports that HookProcessor imports
    if ($pkg eq 'ZmEventNotification::FCM') {
        *{"${pkg}::sendOverFCM"} = sub { };
    } elsif ($pkg eq 'ZmEventNotification::MQTT') {
        *{"${pkg}::sendOverMQTTBroker"} = sub { };
    } elsif ($pkg eq 'ZmEventNotification::DB') {
        *{"${pkg}::updateEventinZmDB"} = sub { };
        *{"${pkg}::getNotesFromEventDB"} = sub { '' };
        *{"${pkg}::tagEventObjects"} = sub { };
    } elsif ($pkg eq 'ZmEventNotification::WebSocketHandler') {
        *{"${pkg}::getNotificationStatusEsControl"} = sub { 0 };
    }
}

use_ok('ZmEventNotification::HookProcessor');
ZmEventNotification::HookProcessor->import(':all');

# ===== isAllowedChannel tests =====
# Config from fixture:
#   event_start_notify_on_hook_success: all
#   event_start_notify_on_hook_fail: none
#   event_end_notify_on_hook_success: fcm,web
#   event_end_notify_on_hook_fail: none

# event_start + success (resCode=0) -> "all" -> any channel allowed
is(isAllowedChannel('event_start', 'fcm',  0), 1, 'event_start success: fcm allowed (all)');
is(isAllowedChannel('event_start', 'web',  0), 1, 'event_start success: web allowed (all)');
is(isAllowedChannel('event_start', 'mqtt', 0), 1, 'event_start success: mqtt allowed (all)');

# event_start + fail (resCode=1) -> "none" -> nothing allowed
is(isAllowedChannel('event_start', 'fcm',  1), '', 'event_start fail: fcm not allowed (none)');
is(isAllowedChannel('event_start', 'web',  1), '', 'event_start fail: web not allowed (none)');

# event_end + success -> "fcm,web"
is(isAllowedChannel('event_end', 'fcm',  0), 1, 'event_end success: fcm allowed');
is(isAllowedChannel('event_end', 'web',  0), 1, 'event_end success: web allowed');
is(isAllowedChannel('event_end', 'mqtt', 0), '', 'event_end success: mqtt not allowed');

# event_end + fail -> "none"
is(isAllowedChannel('event_end', 'fcm',  1), '', 'event_end fail: fcm not allowed');

# Invalid event type
is(isAllowedChannel('bogus', 'fcm', 0), 0, 'invalid event_type returns 0');

done_testing();
