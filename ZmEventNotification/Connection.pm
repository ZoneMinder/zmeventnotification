package ZmEventNotification::Connection;
use strict;
use warnings;
use Exporter 'import';
use JSON;
use ZmEventNotification::Constants qw(:all);
use ZmEventNotification::Config qw(:all);
use ZmEventNotification::Util qw(getConnFields);

our @EXPORT_OK = qw(check_for_duplicate_token checkConnection loadPredefinedConnections);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

sub check_for_duplicate_token {
  my %token_duplicates = ();
  foreach (@main::active_connections) {
    $token_duplicates{$_->{token}}++ if $_->{token};
  }
  foreach (keys %token_duplicates) {
    main::Debug(2, '...'.substr($_,-10).' occurs: '.$token_duplicates{$_}.' times') if $token_duplicates{$_} > 1;
  }
}

sub checkConnection {
  foreach (@main::active_connections) {
    my $curtime = time();
    if ( $_->{state} == PENDING_AUTH ) {

      if ( $curtime - $_->{time} > $auth_config{timeout} ) {
        if ( exists $_->{conn} ) {
          my $conn = $_->{conn};
          main::Error( 'Rejecting '
              . $conn->ip()
              . getConnFields($conn)
              . ' - authentication timeout' );
          $_->{state} = PENDING_DELETE;
          my $str = encode_json(
            { event  => 'auth',
              type   => '',
              status => 'Fail',
              reason => 'NOAUTH'
            }
          );
          eval { $_->{conn}->send_utf8($str); };
          main::Error("Error sending NOAUTH: $@") if $@;
          $_->{conn}->disconnect();
        } # end if exists $_->{conn}
      } # end if curtime - $_->{time} > auth_timeout
    } # end if state == PENDING_AUTH
  } # end foreach active_connections
  @main::active_connections =
    grep { $_->{state} != PENDING_DELETE } @main::active_connections;

  my $fcm_conn =
    scalar grep { $_->{state} == VALID_CONNECTION && $_->{type} == FCM }
    @main::active_connections;
  my $fcm_no_conn =
    scalar grep { $_->{state} == INVALID_CONNECTION && $_->{type} == FCM }
    @main::active_connections;
  my $pend_conn =
    scalar grep { $_->{state} == PENDING_AUTH } @main::active_connections;
  my $mqtt_conn = scalar grep { $_->{type} == MQTT } @main::active_connections;
  my $web_conn =
    scalar grep { $_->{state} == VALID_CONNECTION && $_->{type} == WEB }
    @main::active_connections;
  my $web_no_conn =
    scalar grep { $_->{state} == INVALID_CONNECTION && $_->{type} == WEB }
    @main::active_connections;

  my $escontrol_conn =
    scalar
    grep {
      ($_->{state} == VALID_CONNECTION) and defined($_->{category}) and ($_->{category} eq 'escontrol')
    } @main::active_connections;

  main::Debug(2, 'After tick: TOTAL: '. @main::active_connections." ,  ES_CONTROL: $escontrol_conn, FCM+WEB: $fcm_conn, FCM: $fcm_no_conn, WEB: $web_conn, MQTT:$mqtt_conn, invalid WEB: $web_no_conn, PENDING: $pend_conn");
} # end sub checkConnection

sub loadPredefinedConnections {
  ZmEventNotification::FCM::initFCMTokens() if $fcm_config{enabled};
  ZmEventNotification::MQTT::initMQTT()     if $mqtt_config{enabled};
}

1;
