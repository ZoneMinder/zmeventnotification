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

# Load config first (Util imports Config)
use ZmEventNotification::Config qw(:all);
my $fixtures = File::Spec->catdir($FindBin::Bin, 'fixtures');
my $cfg = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_es.yml'));
my $sec = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_secrets.yml'));
$ZmEventNotification::Config::secrets = $sec;
loadEsConfigSettings($cfg);

use_ok('ZmEventNotification::Util');
ZmEventNotification::Util->import(':all');

# ===== parseDetectResults =====
{
    my ($txt, $json) = parseDetectResults('[a] detected:person--SPLIT--[{"label":"person","confidence":"0.92"}]');
    is($txt, '[a] detected:person', 'parseDetectResults: text portion');
    like($json, qr/"label"/, 'parseDetectResults: json portion contains label');
}

{
    my ($txt, $json) = parseDetectResults('just text no split');
    is($txt, 'just text no split', 'parseDetectResults: no SPLIT returns full text');
    is($json, '[]', 'parseDetectResults: no SPLIT returns empty json array');
}

{
    my ($txt, $json) = parseDetectResults('');
    is($txt, '', 'parseDetectResults: empty string returns empty text');
    is($json, '[]', 'parseDetectResults: empty string returns []');
}

{
    my ($txt, $json) = parseDetectResults(undef);
    is($txt, '', 'parseDetectResults: undef returns empty text');
    is($json, '[]', 'parseDetectResults: undef returns []');
}

# ===== isInList =====
{
    is(isInList('1,2,3', 2), 1, 'isInList: id present');
    is(isInList('1,2,3', 5), '', 'isInList: id absent');
    is(isInList(undef, 1), 1, 'isInList: undef list allows all');
    is(isInList('', 1), 1, 'isInList: empty list allows all');
    is(isInList('-1', 1), 1, 'isInList: -1 allows all');
}

# ===== stripFrameMatchType =====
{
    # keep_frame_match_type is 'yes' (1) from config, so it should NOT strip
    is(stripFrameMatchType('[a] detected:person'), '[a] detected:person',
        'stripFrameMatchType: keeps [a] when config says yes');

    # Temporarily disable keep_frame_match_type
    local $ZmEventNotification::Config::hooks_config{keep_frame_match_type} = 0;
    is(stripFrameMatchType('[a] detected:person'), 'detected:person',
        'stripFrameMatchType: strips [a] when config says no');
    is(stripFrameMatchType('[s] detected:car'), 'detected:car',
        'stripFrameMatchType: strips [s]');
    is(stripFrameMatchType('[x] detected:dog'), 'detected:dog',
        'stripFrameMatchType: strips [x]');
    is(stripFrameMatchType('no_prefix'), 'no_prefix',
        'stripFrameMatchType: no prefix unchanged');
}

# ===== buildPictureUrl =====
{
    # Set up required config
    local $ZmEventNotification::Config::notify_config{picture_url} =
        'https://zm.example.com/zm/index.php?view=image&eid=EVENTID&fid=BESTMATCH&width=600';
    local $ZmEventNotification::Config::notify_config{picture_portal_username} = 'user1';
    local $ZmEventNotification::Config::notify_config{picture_portal_password} = 'p@ss';
    local $ZmEventNotification::Config::hooks_config{event_start_hook} = '/usr/bin/hook.sh';
    local $ZmEventNotification::Config::hooks_config{enabled} = 1;

    my $url = buildPictureUrl(12345, '[a] detected:person', 0, 'test');
    like($url, qr/eid=12345/, 'buildPictureUrl: EVENTID replaced');
    like($url, qr/fid=alarm/, 'buildPictureUrl: BESTMATCH replaced with alarm for [a]');
    like($url, qr/username=user1/, 'buildPictureUrl: username appended');
    like($url, qr/password=p%40ss/, 'buildPictureUrl: password url-encoded');

    # Snapshot match
    my $url_s = buildPictureUrl(999, '[s] detected:car', 0, 'test');
    like($url_s, qr/fid=snapshot/, 'buildPictureUrl: BESTMATCH replaced with snapshot for [s]');

    # Hook failure -> objdetect replaced with snapshot
    local $ZmEventNotification::Config::notify_config{picture_url} =
        'https://zm.example.com/zm/index.php?view=image&eid=EVENTID&fid=objdetect&width=600';
    my $url_fail = buildPictureUrl(999, '[a] motion', 1, 'test');
    like($url_fail, qr/fid=snapshot/, 'buildPictureUrl: objdetect -> snapshot on hook fail');
}

# ===== getInterval =====
{
    is(getInterval('10,20,30', '1,2,3', 2), 20, 'getInterval: correct interval for mid');
    is(getInterval('10,20,30', '1,2,3', 1), 10, 'getInterval: first monitor');
    is(getInterval('10,20,30', '1,2,3', 9), undef, 'getInterval: missing mid returns undef');
}

done_testing();
