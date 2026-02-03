#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../";
use lib "$FindBin::Bin/lib";

use Test::More;
use YAML::XS;
use File::Spec;
use Time::Piece;

require StubZM;

use ZmEventNotification::Config qw(:all);
use_ok('ZmEventNotification::Rules');
ZmEventNotification::Rules->import(':all');

# Load test rules directly into %es_rules
my $fixtures = File::Spec->catdir($FindBin::Bin, 'fixtures');
my $rules_data = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_rules.yml'));
%ZmEventNotification::Config::es_rules = %$rules_data;

# Helper: build an alarm hashref
sub make_alarm {
    my (%opts) = @_;
    return {
        MonitorId => $opts{mid} // 1,
        Name      => $opts{name} // 'TestMonitor',
        EventId   => $opts{eid} // 100,
        Cause     => $opts{cause} // 'detected:person',
        Start     => { Cause => $opts{cause} // 'detected:person' },
        End       => { Cause => $opts{end_cause} // '' },
    };
}

# ===== Monitor with no rules -> default allow =====
{
    my $alarm = make_alarm(mid => 999, cause => 'detected:person');
    my ($allowed, $obj) = isAllowedInRules($alarm);
    is($allowed, 1, 'no rules for monitor 999 -> allowed (default)');
}

# ===== Monitor 1: mute rule matching person, all days, all times =====
# This should MUTE (return 0) when cause matches person
{
    my $alarm = make_alarm(mid => 1, cause => 'detected:person');
    my ($allowed, $obj) = isAllowedInRules($alarm);
    is($allowed, 0, 'monitor 1: person cause matched mute rule -> blocked');
}

# Monitor 1: cause doesn't match person -> not matched by mute rule -> allowed
{
    my $alarm = make_alarm(mid => 1, cause => 'detected:car');
    my ($allowed, $obj) = isAllowedInRules($alarm);
    is($allowed, 1, 'monitor 1: car cause does not match person mute rule -> allowed');
}

# ===== Monitor 2: critical_notify rule matching person|car =====
{
    my $alarm = make_alarm(mid => 2, cause => 'detected:person');
    my ($allowed, $obj) = isAllowedInRules($alarm);
    is($allowed, 1, 'monitor 2: person matches critical_notify -> allowed');
    is($obj->{notification_type}, 'critical', 'monitor 2: notification_type is critical');
}

{
    my $alarm = make_alarm(mid => 2, cause => 'detected:car');
    my ($allowed, $obj) = isAllowedInRules($alarm);
    is($allowed, 1, 'monitor 2: car matches critical_notify -> allowed');
}

{
    my $alarm = make_alarm(mid => 2, cause => 'detected:dog');
    my ($allowed, $obj) = isAllowedInRules($alarm);
    is($allowed, 1, 'monitor 2: dog does not match -> no rule matched -> allowed');
    is_deeply($obj, {}, 'monitor 2: no rule matched -> empty object');
}

# ===== Monitor 3: day-of-week filter set to NONE_MATCH -> never matches =====
{
    my $alarm = make_alarm(mid => 3, cause => 'detected:person');
    my ($allowed, $obj) = isAllowedInRules($alarm);
    is($allowed, 1, 'monitor 3: day filter NONE_MATCH -> rule skipped -> allowed');
}

# ===== No rules for monitor at all -> allowed =====
{
    my $alarm = make_alarm(mid => 42, cause => 'detected:anything');
    my ($allowed, $obj) = isAllowedInRules($alarm);
    is($allowed, 1, 'monitor 42 (no rules) -> allowed');
}

# ===== Time::Piece not installed scenario =====
{
    local $main::is_timepiece = 0;
    my $alarm = make_alarm(mid => 1, cause => 'detected:person');
    my ($allowed, $obj) = isAllowedInRules($alarm);
    is($allowed, 1, 'Time::Piece not installed -> returns error result (1)');
}

# ===== Cause fallback to End cause when Start doesn't have detected: =====
{
    my $alarm = {
        MonitorId => 2,
        Name      => 'TestMon',
        EventId   => 200,
        Cause     => 'detected:person',
        Start     => { Cause => 'Motion' },
        End       => { Cause => 'detected:person' },
    };
    my ($allowed, $obj) = isAllowedInRules($alarm);
    is($allowed, 1, 'cause fallback to End cause -> matches critical_notify');
    is($obj->{notification_type}, 'critical', 'cause fallback: notification_type is critical');
}

done_testing();
