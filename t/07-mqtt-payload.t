#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../";
use lib "$FindBin::Bin/lib";

use Test::More;
use JSON;
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

# Set up WRITER as an in-memory filehandle
my $pipe_output = '';
open(my $writer_fh, '>', \$pipe_output) or die "Cannot open scalar ref: $!";
$writer_fh->autoflush(1);
*main::WRITER = *$writer_fh;

use_ok('ZmEventNotification::MQTT');
ZmEventNotification::MQTT->import(':all');

# Set a known topic
$mqtt_config{topic} = 'zoneminder';

my $alarm_base = {
    MonitorId     => '5',
    EventId       => '12345',
    Name          => 'FrontDoor',
    Cause         => '[a] detected:person,car',
    DetectionJson => [{ label => 'person' }],
};

# ===== Test: Pipe line format =====
{
    $pipe_output = '';
    my $ac = { id => 42, type => MQTT };
    sendOverMQTTBroker({ %$alarm_base }, $ac, 'event_start', 0);

    like($pipe_output, qr/^mqtt_publish--TYPE--/, 'pipe starts with mqtt_publish--TYPE--');
    like($pipe_output, qr/--SPLIT--/, 'pipe contains --SPLIT-- separator');
    my @parts = split(/--SPLIT--/, $pipe_output);
    is(scalar @parts, 3, 'pipe has 3 parts (header, topic, json)');
}

# ===== Test: JSON payload keys =====
{
    $pipe_output = '';
    my $ac = { id => 99, type => MQTT };
    sendOverMQTTBroker({ %$alarm_base }, $ac, 'event_start', 0);

    my @parts = split(/--SPLIT--/, $pipe_output);
    my $json_str = $parts[2];
    chomp $json_str;
    my $data = decode_json($json_str);
    is($data->{monitor}, '5', 'monitor field is MonitorId');
    is($data->{eventid}, '12345', 'eventid field');
    is($data->{state}, 'alarm', 'state is always alarm');
    is($data->{eventtype}, 'event_start', 'eventtype field');
    ok(defined $data->{name}, 'name field present');
    ok(defined $data->{detection}, 'detection field present');
}

# ===== Test: Topic format =====
{
    $pipe_output = '';
    my $ac = { id => 1, type => MQTT };
    sendOverMQTTBroker({ %$alarm_base }, $ac, 'event_start', 0);

    my @parts = split(/--SPLIT--/, $pipe_output);
    my $topic = $parts[1];
    is($topic, 'zoneminder/5', 'topic = config_topic/MonitorId');
}

# ===== Test: event_end name prefix =====
{
    $pipe_output = '';
    my $ac = { id => 2, type => MQTT };
    sendOverMQTTBroker({ %$alarm_base }, $ac, 'event_end', 0);

    my @parts = split(/--SPLIT--/, $pipe_output);
    my $data = decode_json($parts[2]);
    like($data->{name}, qr/^Ended:/, 'event_end: name prefixed with Ended:');
}

# ===== Test: event_start name format =====
{
    $pipe_output = '';
    my $ac = { id => 3, type => MQTT };
    my $alarm = { %$alarm_base };
    sendOverMQTTBroker($alarm, $ac, 'event_start', 0);

    my @parts = split(/--SPLIT--/, $pipe_output);
    my $data = decode_json($parts[2]);
    # Name format: "MonName:(EID) Cause"
    like($data->{name}, qr/FrontDoor:\(12345\)/, 'event_start name has MonName:(EID)');
}

# ===== Test: DetectionJson passed through =====
{
    $pipe_output = '';
    my $ac = { id => 4, type => MQTT };
    my $det = [{ label => 'person', confidence => 0.95 }];
    my $alarm = { %$alarm_base, DetectionJson => $det };
    sendOverMQTTBroker($alarm, $ac, 'event_start', 0);

    my @parts = split(/--SPLIT--/, $pipe_output);
    my $data = decode_json($parts[2]);
    is_deeply($data->{detection}, $det, 'DetectionJson passed through to detection field');
}

# ===== Test: hookvalue =====
{
    $pipe_output = '';
    my $ac = { id => 5, type => MQTT };
    sendOverMQTTBroker({ %$alarm_base }, $ac, 'event_start', 1);

    my @parts = split(/--SPLIT--/, $pipe_output);
    my $data = decode_json($parts[2]);
    is($data->{hookvalue}, 1, 'hookvalue reflects resCode');
}

done_testing();
