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

# Mock secrets object that supports ->val() like Config::IniFiles
{
    package MockSecrets;
    sub new  { bless $_[1] // {}, $_[0] }
    sub val  {
        my ($self, $section, $key) = @_;
        return $self->{$section}{$key};
    }
}

# Load config (secrets needed for getZmUserId)
my $fixtures = File::Spec->catdir($FindBin::Bin, 'fixtures');
my $cfg = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_es.yml'));
my $sec = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_secrets.yml'));
$ZmEventNotification::Config::secrets = MockSecrets->new($sec);
loadEsConfigSettings($cfg);

use_ok('ZmEventNotification::DB');
ZmEventNotification::DB->import(':all');

# Reset spies before each group
sub reset_spies {
    ZoneMinder::Tag->_reset_spy();
    ZoneMinder::Event_Tag->_reset_spy();
    $ZmEventNotification::DB::cached_zm_user_id = undef;
}

# ===== Version < 1.37.44 -> early return =====
{
    reset_spies();
    local $ZoneMinder::_zm_version = '1.36.0';
    tagEventObjects(100, ['person', 'car']);
    my @tag_calls = ZoneMinder::Tag->_spy_find_one_calls();
    is(scalar @tag_calls, 0, 'version < 1.37.44: no tag operations');
}

# ===== Version >= 1.37.44 -> proceeds =====
{
    reset_spies();
    local $ZoneMinder::_zm_version = '1.38.0';
    ZoneMinder::Tag->_set_next_find_one(undef);  # force creation
    tagEventObjects(200, ['person']);
    my @tag_calls = ZoneMinder::Tag->_spy_find_one_calls();
    ok(scalar @tag_calls > 0, 'version >= 1.37.44: tag operations proceed');
}

# ===== Duplicate labels deduplicated =====
{
    reset_spies();
    local $ZoneMinder::_zm_version = '1.38.0';
    ZoneMinder::Tag->_set_next_find_one(undef);
    tagEventObjects(300, ['person', 'person', 'car']);
    my @find_calls = ZoneMinder::Tag->_spy_find_one_calls();
    is(scalar @find_calls, 2, 'duplicates: only 2 find_one calls for person,person,car');
}

# ===== Existing tag: save called with LastAssignedDate =====
{
    reset_spies();
    local $ZoneMinder::_zm_version = '1.38.0';
    my $existing_tag = bless { Id => 42 }, 'ZoneMinder::Tag';
    ZoneMinder::Tag->_set_next_find_one($existing_tag);
    tagEventObjects(400, ['person']);
    my @save_calls = ZoneMinder::Tag->_spy_save_calls();
    ok(scalar @save_calls > 0, 'existing tag: save called');
    ok(defined $save_calls[0]{data}{LastAssignedDate}, 'existing tag: LastAssignedDate updated');
    ok(!defined $save_calls[0]{data}{Name}, 'existing tag: Name not set (update only)');
}

# ===== New tag: new() + save with Name, CreateDate, CreatedBy, LastAssignedDate =====
{
    reset_spies();
    local $ZoneMinder::_zm_version = '1.38.0';
    ZoneMinder::Tag->_set_next_find_one(undef);  # not found
    tagEventObjects(500, ['car']);
    my @save_calls = ZoneMinder::Tag->_spy_save_calls();
    # First save is for the new tag creation
    ok(scalar @save_calls >= 1, 'new tag: save called');
    is($save_calls[0]{data}{Name}, 'car', 'new tag: Name set');
    ok(defined $save_calls[0]{data}{CreateDate}, 'new tag: CreateDate set');
    ok(defined $save_calls[0]{data}{CreatedBy}, 'new tag: CreatedBy set');
    ok(defined $save_calls[0]{data}{LastAssignedDate}, 'new tag: LastAssignedDate set');
}

# ===== Event_Tag created for each unique label =====
{
    reset_spies();
    local $ZoneMinder::_zm_version = '1.38.0';
    ZoneMinder::Tag->_set_next_find_one(undef);
    tagEventObjects(600, ['person', 'car', 'dog']);
    my @et_calls = ZoneMinder::Event_Tag->_spy_save_calls();
    is(scalar @et_calls, 3, 'Event_Tag save called 3 times for 3 unique labels');
    # Check EventId is set correctly
    for my $call (@et_calls) {
        is($call->{data}{EventId}, 600, 'Event_Tag has correct EventId');
    }
}

# ===== getZmUserId caching =====
{
    reset_spies();
    local $ZoneMinder::_zm_version = '1.38.0';
    ZoneMinder::User->_set_next_find_one({ Id => 7 });
    ZoneMinder::Tag->_set_next_find_one(undef);

    tagEventObjects(700, ['a']);
    tagEventObjects(701, ['b']);

    # getZmUserId should have been called once and cached
    # We can verify via the User spy, but our stub doesn't track calls.
    # Instead, verify both calls succeeded (no errors)
    my @et_calls = ZoneMinder::Event_Tag->_spy_save_calls();
    is(scalar @et_calls, 2, 'two tagEventObjects calls both created Event_Tags');
    is($et_calls[0]{data}{AssignedBy}, 7, 'first call used resolved uid');
    is($et_calls[1]{data}{AssignedBy}, 7, 'second call used cached uid');
}

# ===== getZmUserId with no secrets returns 0 =====
{
    reset_spies();
    $ZmEventNotification::DB::cached_zm_user_id = undef;
    local $ZmEventNotification::Config::secrets = undef;
    my $uid = getZmUserId();
    is($uid, 0, 'no secrets -> uid=0');
}

done_testing();
