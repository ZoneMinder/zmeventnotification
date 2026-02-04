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
use MIME::Base64;

require StubZM;

use ZmEventNotification::Config qw(:all);
use ZmEventNotification::Constants qw(:all);

# Load config
my $fixtures = File::Spec->catdir($FindBin::Bin, 'fixtures');
my $cfg = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_es.yml'));
my $sec = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_secrets.yml'));
$ZmEventNotification::Config::secrets = $sec;
loadEsConfigSettings($cfg);

# ---- Mock LWP::UserAgent and HTTP::Request ----
{
    package MockHTTPResponse;
    sub new            { bless { content => '{}', success => 1 }, shift }
    sub is_success     { $_[0]->{success} }
    sub decoded_content { $_[0]->{content} }
    sub status_line    { 'OK' }
    sub content        { $_[0]->{content} }
}

my @captured_requests;
my $mock_response = MockHTTPResponse->new();

{
    package LWP::UserAgent;
    sub new     { bless {}, shift }
    sub request {
        my ($self, $req) = @_;
        push @captured_requests, $req;
        return $mock_response;
    }
    sub import  { 1 }
    $INC{'LWP/UserAgent.pm'} = 1;
}

{
    package HTTP::Request;
    sub new {
        my ($class, $method, $uri) = @_;
        bless { method => $method, uri => $uri, headers => {}, content => '' }, $class;
    }
    sub header  { my ($self, %h) = @_; @{$self->{headers}}{keys %h} = values %h }
    sub content {
        my ($self, $val) = @_;
        if (defined $val) { $self->{content} = $val; return }
        return $self->{content};
    }
    sub import  { 1 }
    $INC{'HTTP/Request.pm'} = 1;
}

# Stub other deps
for my $pkg (qw(
    ZmEventNotification::MQTT
    ZmEventNotification::DB
    ZmEventNotification::WebSocketHandler
)) {
    (my $file = $pkg) =~ s{::}{/}g;
    $INC{"$file.pm"} = 1;
    no strict 'refs';
    *{"${pkg}::import"} = sub { 1 };
    if ($pkg eq 'ZmEventNotification::MQTT') {
        *{"${pkg}::sendOverMQTTBroker"} = sub { };
    } elsif ($pkg eq 'ZmEventNotification::DB') {
        *{"${pkg}::updateEventinZmDB"} = sub { };
        *{"${pkg}::getNotesFromEventDB"} = sub { '' };
        *{"${pkg}::tagEventObjects"} = sub { };
    } elsif ($pkg eq 'ZmEventNotification::WebSocketHandler') {
        *{"${pkg}::getNotificationStatusEsControl"} = sub { 0 };
    }
}

use_ok('ZmEventNotification::FCM');
ZmEventNotification::FCM->import(':all');

# Set up WRITER
my $pipe_output = '';
open(my $writer_fh, '>', \$pipe_output) or die "Cannot open scalar ref: $!";
$writer_fh->autoflush(1);
*main::WRITER = *$writer_fh;

# ===== _base64url_encode =====

{
    # Standard base64url: + -> -, / -> _, no trailing =
    my $input = "\x00\xff\xfe";  # produces +/= in standard base64
    my $result = ZmEventNotification::FCM::_base64url_encode($input);
    unlike($result, qr/\+/, 'no + in base64url');
    unlike($result, qr/\//, 'no / in base64url');
    unlike($result, qr/=$/, 'no trailing = in base64url');
    # Verify it's valid base64url characters
    like($result, qr/^[A-Za-z0-9_-]+$/, 'only valid base64url chars');
}

{
    my $result = ZmEventNotification::FCM::_base64url_encode("Hello World");
    is($result, 'SGVsbG8gV29ybGQ', '_base64url_encode("Hello World")');
}

# ===== _check_monthly_limit =====

{
    # Under limit -> returns 0
    my $obj = {
        token => 'test_token_1234567890',
        invocations => { count => 100, at => (localtime)[4] },
    };
    my $result = ZmEventNotification::FCM::_check_monthly_limit($obj);
    is($result, 0, '_check_monthly_limit: under limit returns 0');
}

{
    # Over limit -> returns 1
    my $obj = {
        token => 'test_token_1234567890',
        invocations => { count => DEFAULT_MAX_FCM_PER_MONTH_PER_TOKEN + 1, at => (localtime)[4] },
    };
    my $result = ZmEventNotification::FCM::_check_monthly_limit($obj);
    is($result, 1, '_check_monthly_limit: over limit returns 1');
}

{
    # Month rollover resets count
    my $curmonth = (localtime)[4];
    my $other_month = ($curmonth + 1) % 12;
    my $obj = {
        token => 'test_token_1234567890',
        invocations => { count => 9999, at => $other_month },
    };
    my $result = ZmEventNotification::FCM::_check_monthly_limit($obj);
    is($result, 0, '_check_monthly_limit: month rollover resets, returns 0');
    is($obj->{invocations}{count}, 0, 'count reset to 0 after month change');
}

# ===== sendOverFCMV1 proxy mode =====

my $alarm_base = {
    MonitorId => '7',
    EventId   => '55555',
    Name      => 'Garage',
    Cause     => '[a] detected:person',
};

# Configure proxy mode
$fcm_config{service_account_file} = undef;
$fcm_config{v1_key} = 'test-proxy-key';
$fcm_config{v1_url} = 'https://proxy.example.com/push';
$fcm_config{date_format} = '%H:%M';
$fcm_config{android_priority} = 'high';
$fcm_config{android_ttl} = '600';
$fcm_config{replace_push_messages} = 0;
$fcm_config{log_raw_message} = 0;
$fcm_config{log_message_id} = 'NONE';

{
    # Proxy mode: Android payload
    @captured_requests = ();
    $pipe_output = '';
    my $obj = {
        token       => 'android_token_abcdef1234',
        platform    => 'android',
        badge       => 3,
        invocations => { count => 10, at => (localtime)[4] },
        state       => INVALID_CONNECTION,
        appversion  => '2.0',
    };
    local $notify_config{tag_alarm_event_id} = 0;
    local $notify_config{picture_url} = undef;
    local $notify_config{include_picture} = 0;

    sendOverFCMV1({ %$alarm_base }, $obj, 'event_start', 0);

    ok(scalar @captured_requests > 0, 'proxy android: request sent');
    my $body = decode_json($captured_requests[-1]->{content});
    is($body->{token}, 'android_token_abcdef1234', 'proxy android: token');
    ok(defined $body->{title}, 'proxy android: title present');
    ok(defined $body->{body}, 'proxy android: body present');
    is($body->{badge}, 4, 'proxy android: badge incremented');
    is($body->{data}{mid}, '7', 'proxy android: data.mid');
    is($body->{data}{eid}, '55555', 'proxy android: data.eid');
    is($body->{android}{icon}, 'ic_stat_notification', 'proxy android: icon');
    is($body->{android}{priority}, 'high', 'proxy android: priority');
}

{
    # Proxy mode: iOS payload
    @captured_requests = ();
    $pipe_output = '';
    my $obj = {
        token       => 'ios_token_xyz9876543',
        platform    => 'ios',
        badge       => 0,
        invocations => { count => 5, at => (localtime)[4] },
        state       => INVALID_CONNECTION,
        appversion  => '2.0',
    };
    local $notify_config{tag_alarm_event_id} = 0;
    local $notify_config{picture_url} = undef;
    local $notify_config{include_picture} = 0;

    sendOverFCMV1({ %$alarm_base }, $obj, 'event_start', 0);

    my $body = decode_json($captured_requests[-1]->{content});
    ok(defined $body->{ios}, 'proxy ios: ios section present');
    is($body->{ios}{thread_id}, 'zmninja_alarm', 'proxy ios: thread_id');
    ok(defined $body->{ios}{headers}, 'proxy ios: headers present');
}

{
    # Proxy mode: event_end title has "Ended:" prefix
    @captured_requests = ();
    $pipe_output = '';
    my $obj = {
        token       => 'tok_end_test_1234567890',
        platform    => 'android',
        badge       => 0,
        invocations => { count => 0, at => (localtime)[4] },
        state       => INVALID_CONNECTION,
        appversion  => 'unknown',
    };
    local $notify_config{tag_alarm_event_id} = 0;

    sendOverFCMV1({ %$alarm_base }, $obj, 'event_end', 0);

    my $body = decode_json($captured_requests[-1]->{content});
    like($body->{title}, qr/^Ended:/, 'proxy: event_end title starts with Ended:');
    like($body->{body}, qr/ended/, 'proxy: event_end body contains ended');
}

{
    # Proxy mode: tag_alarm_event_id adds (EID) to title
    @captured_requests = ();
    $pipe_output = '';
    my $obj = {
        token       => 'tok_tag_test_1234567890',
        platform    => 'android',
        badge       => 0,
        invocations => { count => 0, at => (localtime)[4] },
        state       => INVALID_CONNECTION,
        appversion  => '2.0',
    };
    local $notify_config{tag_alarm_event_id} = 1;

    sendOverFCMV1({ %$alarm_base }, $obj, 'event_start', 0);

    my $body = decode_json($captured_requests[-1]->{content});
    like($body->{title}, qr/\(55555\)/, 'tag_alarm_event_id: title contains (EID)');
}

{
    # Proxy mode: replace_push_messages sets android.tag
    @captured_requests = ();
    $pipe_output = '';
    local $fcm_config{replace_push_messages} = 1;
    my $obj = {
        token       => 'tok_replace_1234567890',
        platform    => 'android',
        badge       => 0,
        invocations => { count => 0, at => (localtime)[4] },
        state       => INVALID_CONNECTION,
        appversion  => '2.0',
    };
    local $notify_config{tag_alarm_event_id} = 0;

    sendOverFCMV1({ %$alarm_base }, $obj, 'event_start', 0);

    my $body = decode_json($captured_requests[-1]->{content});
    is($body->{android}{tag}, 'zmninjapush', 'replace_push_messages: android tag set');
}

{
    # Proxy mode: replace_push_messages sets ios collapse-id
    @captured_requests = ();
    $pipe_output = '';
    local $fcm_config{replace_push_messages} = 1;
    my $obj = {
        token       => 'tok_replace_ios_1234567890',
        platform    => 'ios',
        badge       => 0,
        invocations => { count => 0, at => (localtime)[4] },
        state       => INVALID_CONNECTION,
        appversion  => '2.0',
    };
    local $notify_config{tag_alarm_event_id} = 0;

    sendOverFCMV1({ %$alarm_base }, $obj, 'event_start', 0);

    my $body = decode_json($captured_requests[-1]->{content});
    is($body->{ios}{headers}{'apns-collapse-id'}, 'zmninjapush', 'replace_push_messages: ios collapse-id set');
}

{
    # Proxy mode: android_ttl
    @captured_requests = ();
    $pipe_output = '';
    local $fcm_config{android_ttl} = '300';
    local $fcm_config{replace_push_messages} = 0;
    my $obj = {
        token       => 'tok_ttl_test_1234567890',
        platform    => 'android',
        badge       => 0,
        invocations => { count => 0, at => (localtime)[4] },
        state       => INVALID_CONNECTION,
        appversion  => '2.0',
    };
    local $notify_config{tag_alarm_event_id} = 0;

    sendOverFCMV1({ %$alarm_base }, $obj, 'event_start', 0);

    my $body = decode_json($captured_requests[-1]->{content});
    is($body->{android}{ttl}, '300', 'proxy: android_ttl passed through');
}

{
    # Proxy mode: android channel set for modern app
    @captured_requests = ();
    $pipe_output = '';
    my $obj = {
        token       => 'tok_channel_1234567890',
        platform    => 'android',
        badge       => 0,
        invocations => { count => 0, at => (localtime)[4] },
        state       => INVALID_CONNECTION,
        appversion  => '2.0',
    };
    local $notify_config{tag_alarm_event_id} = 0;
    local $fcm_config{replace_push_messages} = 0;

    sendOverFCMV1({ %$alarm_base }, $obj, 'event_start', 0);

    my $body = decode_json($captured_requests[-1]->{content});
    is($body->{android}{channel}, 'zmninja', 'modern app: android channel set');
}

{
    # Proxy mode: legacy app does NOT get channel
    @captured_requests = ();
    $pipe_output = '';
    my $obj = {
        token       => 'tok_legacy_1234567890',
        platform    => 'android',
        badge       => 0,
        invocations => { count => 0, at => (localtime)[4] },
        state       => INVALID_CONNECTION,
        appversion  => 'unknown',
    };
    local $notify_config{tag_alarm_event_id} = 0;
    local $fcm_config{replace_push_messages} = 0;

    sendOverFCMV1({ %$alarm_base }, $obj, 'event_start', 0);

    my $body = decode_json($captured_requests[-1]->{content});
    ok(!defined $body->{android}{channel}, 'legacy app: no android channel');
}

# ===== Pipe output: fcm_notification line format =====
{
    $pipe_output = '';
    my $obj = {
        token       => 'tok_pipe_test_1234567890',
        platform    => 'android',
        badge       => 2,
        invocations => { count => 50, at => (localtime)[4] },
        state       => INVALID_CONNECTION,
        appversion  => '2.0',
    };
    local $notify_config{tag_alarm_event_id} = 0;

    sendOverFCMV1({ %$alarm_base }, $obj, 'event_start', 0);

    like($pipe_output, qr/fcm_notification--TYPE--/, 'pipe output contains fcm_notification--TYPE--');
    my @lines = split /\n/, $pipe_output;
    my $fcm_line = $lines[0];
    my @parts = split /--SPLIT--/, $fcm_line;
    is(scalar @parts, 4, 'fcm_notification has 4 --SPLIT-- parts');
}

# ===== Proxy mode: picture URL inclusion/exclusion =====
{
    @captured_requests = ();
    $pipe_output = '';
    local $notify_config{picture_url} = 'http://example.com/snap?eid=EVENTID';
    local $notify_config{include_picture} = 1;
    local $hooks_config{event_start_hook} = '/usr/bin/detect';
    local $hooks_config{enabled} = 1;
    my $obj = {
        token       => 'tok_pic_test_1234567890',
        platform    => 'android',
        badge       => 0,
        invocations => { count => 0, at => (localtime)[4] },
        state       => INVALID_CONNECTION,
        appversion  => '2.0',
    };
    local $notify_config{tag_alarm_event_id} = 0;

    sendOverFCMV1({ %$alarm_base }, $obj, 'event_start', 0);

    my $body = decode_json($captured_requests[-1]->{content});
    ok(defined $body->{image_url}, 'proxy: picture URL included when configured');
}

{
    @captured_requests = ();
    $pipe_output = '';
    local $notify_config{picture_url} = undef;
    local $notify_config{include_picture} = 0;
    my $obj = {
        token       => 'tok_nopic_1234567890',
        platform    => 'android',
        badge       => 0,
        invocations => { count => 0, at => (localtime)[4] },
        state       => INVALID_CONNECTION,
        appversion  => '2.0',
    };
    local $notify_config{tag_alarm_event_id} = 0;

    sendOverFCMV1({ %$alarm_base }, $obj, 'event_start', 0);

    my $body = decode_json($captured_requests[-1]->{content});
    ok(!defined $body->{image_url}, 'proxy: picture URL excluded when not configured');
}

done_testing();
