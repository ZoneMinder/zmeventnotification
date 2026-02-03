#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../";
use lib "$FindBin::Bin/lib";

use Test::More;
use YAML::XS;
use File::Spec;

# Load stubs first
require StubZM;

use_ok('ZmEventNotification::Config');
ZmEventNotification::Config->import(':all');

# --- Load test fixtures ---
my $fixtures = File::Spec->catdir($FindBin::Bin, 'fixtures');
my $cfg = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_es.yml'));
my $sec = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_secrets.yml'));

# Point the package-level secrets at our test secrets
$ZmEventNotification::Config::secrets = $sec;

# --- Simple string retrieval ---
is(config_get_val($cfg, 'network', 'port', undef), 9000, 'simple int retrieval');
is(config_get_val($cfg, 'network', 'address', undef), '[::]', 'simple string retrieval');

# --- Default value when key is missing ---
is(config_get_val($cfg, 'network', 'nonexistent', 'fallback'), 'fallback', 'default for missing key');
is(config_get_val($cfg, 'nosection', 'nokey', 'def'), 'def', 'default for missing section');

# --- yes/no boolean conversion ---
is(config_get_val($cfg, 'auth', 'enable', undef), 1, 'yes -> 1');
is(config_get_val($cfg, 'mqtt', 'enable', undef), 0, 'no -> 0');

# --- Secret token resolution (! prefix) ---
is(config_get_val($cfg, 'ssl', 'cert', undef), '/tmp/test_cert.pem', 'secret resolution for cert');
is(config_get_val($cfg, 'ssl', 'key', undef), '/tmp/test_key.pem', 'secret resolution for key');
is(config_get_val($cfg, 'mqtt', 'username', undef), 'mqttuser', 'secret resolution for mqtt user');
is(config_get_val($cfg, 'mqtt', 'password', undef), 'mqttpass', 'secret resolution for mqtt pass');

# --- Secret in customize section ---
is(config_get_val($cfg, 'customize', 'picture_portal_username', undef), 'testuser', 'secret picture_portal_username');
is(config_get_val($cfg, 'customize', 'picture_portal_password', undef), 'testpass', 'secret picture_portal_password');

# --- ${template} substitution ---
# token_file references ${base_data_path}
my $token_file = config_get_val($cfg, 'fcm', 'token_file', undef);
like($token_file, qr{/var/lib/zmeventnotification/push/tokens\.txt}, 'template substitution in token_file');

# --- Nested section lookup ---
is(config_get_val($cfg, 'customize', 'es_debug_level', undef), 4, 'nested customize section');
is(config_get_val($cfg, 'customize', 'event_check_interval', undef), 5, 'event_check_interval');

# --- Missing secret triggers fatal ---
{
    my $bad_cfg = { test => { val => '!NONEXISTENT_TOKEN' } };
    eval { config_get_val($bad_cfg, 'test', 'val', undef) };
    like($@, qr/Token.*not found|FATAL/, 'missing secret token triggers fatal');
}

# --- Nil secrets triggers fatal ---
{
    local $ZmEventNotification::Config::secrets = undef;
    my $bad_cfg = { test => { val => '!SOME_TOKEN' } };
    eval { config_get_val($bad_cfg, 'test', 'val', undef) };
    like($@, qr/No secret file|FATAL/, 'no secrets file triggers fatal');
}

# --- Whitespace trimming ---
{
    my $cfg_ws = { sect => { key => '  hello  ' } };
    is(config_get_val($cfg_ws, 'sect', 'key', undef), 'hello', 'whitespace is trimmed');
}

# --- loadEsConfigSettings smoke test ---
$cfg->{general}{secrets} = File::Spec->catfile($fixtures, 'test_secrets.yml');
$ZmEventNotification::Config::config_obj = $cfg;
$ZmEventNotification::Config::secrets = $sec;

eval { loadEsConfigSettings($cfg) };
is($@, '', 'loadEsConfigSettings does not die');
is($ZmEventNotification::Config::server_config{port}, 9000, 'server_config port loaded');
is($ZmEventNotification::Config::auth_config{enabled}, 1, 'auth enabled loaded');
is($ZmEventNotification::Config::hooks_config{enabled}, 1, 'hooks enabled loaded');

done_testing();
