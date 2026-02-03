#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../";
use lib "$FindBin::Bin/lib";

use Test::More;
use JSON;

require StubZM;

use ZmEventNotification::Config qw(:all);
use ZmEventNotification::Util qw(parseDetectResults);

# ===== Contract: --SPLIT-- format between Python producer and Perl consumer =====

# Typical output from zm_detect.py
my $good_output = '[a] detected:person,car--SPLIT--{"labels":["person","car"],"boxes":[[100,200,300,400],[150,250,350,450]],"frame_id":"alarm","confidences":[0.95,0.87],"image_dimensions":{"resized":[416,416]}}';

{
    my ($txt, $json_str) = parseDetectResults($good_output);
    is($txt, '[a] detected:person,car', 'contract: text portion parsed');

    my $json;
    eval { $json = decode_json($json_str) };
    is($@, '', 'contract: JSON portion is valid JSON');
    ok(exists $json->{labels}, 'contract: JSON has labels key');
    ok(exists $json->{boxes}, 'contract: JSON has boxes key');
    ok(exists $json->{confidences}, 'contract: JSON has confidences key');
    ok(exists $json->{frame_id}, 'contract: JSON has frame_id key');
    is(ref $json->{labels}, 'ARRAY', 'contract: labels is an array');
    is($json->{labels}[0], 'person', 'contract: first label is person');
    is($json->{frame_id}, 'alarm', 'contract: frame_id is alarm');
}

# Snapshot frame output
my $snapshot_output = '[s] detected:dog--SPLIT--{"labels":["dog"],"boxes":[[10,20,30,40]],"frame_id":"snapshot","confidences":[0.88],"image_dimensions":null}';

{
    my ($txt, $json_str) = parseDetectResults($snapshot_output);
    is($txt, '[s] detected:dog', 'contract snapshot: text portion');

    my $json = decode_json($json_str);
    is($json->{frame_id}, 'snapshot', 'contract snapshot: frame_id');
}

# No detections -> exit code 1, no output
{
    my ($txt, $json_str) = parseDetectResults('');
    is($txt, '', 'no detections: empty text');
    is($json_str, '[]', 'no detections: empty JSON array');
}

# Single detection with special characters in label
my $special_output = '[a] detected:person (wearing hat)--SPLIT--{"labels":["person (wearing hat)"],"boxes":[[0,0,100,100]],"frame_id":"alarm","confidences":[0.75],"image_dimensions":null}';

{
    my ($txt, $json_str) = parseDetectResults($special_output);
    like($txt, qr/person \(wearing hat\)/, 'special chars: text preserves parens');
    my $json = decode_json($json_str);
    is($json->{labels}[0], 'person (wearing hat)', 'special chars: label preserved in JSON');
}

done_testing();
