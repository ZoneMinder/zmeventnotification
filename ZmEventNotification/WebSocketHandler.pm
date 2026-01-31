package ZmEventNotification::WebSocketHandler;
use strict;
use warnings;
use Exporter 'import';
use JSON;

use ZmEventNotification::Constants qw(:all);
use ZmEventNotification::Config qw(:all);
use ZmEventNotification::Util qw(getObjectForConn getConnFields isValidMonIntList);
use ZmEventNotification::FCM qw(saveFCMTokens);
use ZmEventNotification::DB qw(getAllMonitorIds);

our @EXPORT_OK = qw(
  processIncomingMessage validateAuth processEsControlCommand
  getNotificationStatusEsControl populateEsControlNotification
);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

sub getNotificationStatusEsControl {
  my $id = shift;
  if ( !exists $escontrol_interface_settings{notifications}{$id} ) {
    main::Error(
      "Hmm, Monitor:$id does not exist in control interface, treating it as force notify..."
    );
    return ESCONTROL_FORCE_NOTIFY;
  } else {
    return $escontrol_interface_settings{notifications}{$id};
  }
}

sub populateEsControlNotification {
  return if !$escontrol_config{enabled};
  my $found = 0;
  foreach my $monitor ( values(%main::monitors) ) {
    my $id = $monitor->{Id};
    if ( !exists $escontrol_interface_settings{notifications}{$id} ) {
      $escontrol_interface_settings{notifications}{$id} =
        ESCONTROL_DEFAULT_NOTIFY;
      $found = 1;
      main::Debug(2, "ESCONTROL_INTERFACE: Discovered new monitor:$id, settings notification to ESCONTROL_DEFAULT_NOTIFY");
    }
  }
  main::saveEsControlSettings() if $found;
}

sub processEsControlCommand {
  return if !$escontrol_config{enabled};

  my ( $json, $conn ) = @_;

  my $obj = getObjectForConn($conn);
  if ( !$obj ) {
    main::Error('ESCONTROL error matching connection to object');
    return;
  }

  if ( $obj->{category} ne 'escontrol' ) {

    my $str = encode_json(
      { event   => 'escontrol',
        type    => 'command',
        status  => 'Fail',
        reason  => 'NOTCONTROL',
      }
    );
    eval { $conn->send_utf8($str); };
    main::Error("Error sending NOT CONTROL: $@") if $@;

    return;
  }

  if ( !$json->{data} ) {
    my $str = encode_json(
      { event  => 'escontrol',
        type   => 'command',
        status => 'Fail',
        reason => 'NODATA'
      }
    );
    eval { $conn->send_utf8($str); };
    main::Error("Error sending ADMIN NO DATA: $@") if $@;

    return;
  }

  if ( $json->{data}->{command} eq 'get' ) {

    my $str = encode_json(
      { event    => 'escontrol',
        type     => '',
        status   => 'Success',
        request  => $json,
        response => encode_json( \%escontrol_interface_settings )
      }
    );
    eval { $conn->send_utf8($str); };
    main::Error("Error sending message: $@") if $@;

  } elsif ( $json->{data}->{command} eq 'mute' ) {
    main::Info('ESCONTROL: Admin Interface: Mute notifications');

    my @mids;
    if ( $json->{data}->{monitors} ) {
      @mids = @{ $json->{data}->{monitors} };
    } else {
      @mids = getAllMonitorIds();
    }

    foreach my $mid (@mids) {
      $escontrol_interface_settings{notifications}{$mid} = ESCONTROL_FORCE_MUTE;
      main::Debug(2, "ESCONTROL: setting notification for Mid:$mid to ESCONTROL_FORCE_MUTE");
    }

    main::saveEsControlSettings();
    my $str = encode_json(
      { event   => 'escontrol',
        type    => '',
        status  => 'Success',
        request => $json
      }
    );
    eval { $conn->send_utf8($str); };
    main::Error("Error sending message: $@") if $@;

  } elsif ( $json->{data}->{command} eq 'unmute' ) {
    main::Info('ESCONTROL: Admin Interface: Unmute notifications');

    my @mids;
    if ( $json->{data}->{monitors} ) {
      @mids = @{ $json->{data}->{monitors} };
    } else {
      @mids = getAllMonitorIds();
    }

    foreach my $mid (@mids) {
      $escontrol_interface_settings{notifications}{$mid} =
        ESCONTROL_FORCE_NOTIFY;
      main::Debug(2, "ESCONTROL: setting notification for Mid:$mid to ESCONTROL_FORCE_NOTIFY");
    }

    main::saveEsControlSettings();
    my $str = encode_json(
      { event   => 'escontrol',
        type    => '',
        status  => 'Success',
        request => $json
      }
    );
    eval { $conn->send_utf8($str); };
    main::Error("Error sending message: $@") if $@;

  } elsif ( $json->{data}->{command} eq 'edit' ) {
    my $key = $json->{data}->{key};
    my $val = $json->{data}->{val};
    main::Info("ESCONTROL_INTERFACE: Change $key to $val");
    $escontrol_interface_settings{$key} = $val;
    main::saveEsControlSettings();
    main::Info('ESCONTROL_INTERFACE: --- Doing a complete reload of config --');
    main::loadEsConfigSettings();

    my $str = encode_json(
      { event   => 'escontrol',
        type    => '',
        status  => 'Success',
        request => $json
      }
    );
    eval { $conn->send_utf8($str); };
    main::Error("Error sending message: $@") if $@;

  } elsif ( $json->{data}->{command} eq 'restart' ) {
    main::Info('ES_CONTROL: restart ES');

    my $str = encode_json(
      { event   => 'escontrol',
        type    => 'command',
        status  => 'Success',
        request => $json
      }
    );
    eval { $conn->send_utf8($str); };
    main::Error("Error sending message: $@") if $@;
    main::restartES();

  } elsif ( $json->{data}->{command} eq 'reset' ) {
    main::Info('ES_CONTROL: reset admin commands');

    my $str = encode_json(
      { event   => 'escontrol',
        type    => 'command',
        status  => 'Success',
        request => $json
      }
    );
    eval { $conn->send_utf8($str); };
    main::Error("Error sending message: $@") if $@;
    %escontrol_interface_settings = ( notifications => {} );
    populateEsControlNotification();
    main::saveEsControlSettings();
    main::Info('ESCONTROL_INTERFACE: --- Doing a complete reload of config --');
    main::loadEsConfigSettings();

  } else {
    my $str = encode_json(
      { event   => $json->{escontrol},
        type    => 'command',
        status  => 'Fail',
        reason  => 'NOTSUPPORTED',
        request => $json
      }
    );
    eval { $conn->send_utf8($str); };
    main::Error("Error sending NOTSUPPORTED: $@") if $@;
  }
}

sub validateAuth {
  my ( $u, $p, $c ) = @_;

  # not an ES control auth
  if ( $c eq 'normal' ) {
    return 1 unless $auth_config{enabled};

    return 0 if ( $u eq '' || $p eq '' );
    my $sql = 'SELECT `Password` FROM `Users` WHERE `Username`=?';
    my $sth = $main::dbh->prepare_cached($sql)
      or main::Fatal( "Can't prepare '$sql': " . $main::dbh->errstr() );
    my $res = $sth->execute($u)
      or main::Fatal( "Can't execute: " . $sth->errstr() );
    my $state = $sth->fetchrow_hashref();
    $sth->finish();

    if ($state) {
      if (substr($state->{Password},0,4) eq '-ZM-') {
        main::Error("The password for $u has not been migrated in ZM. Please log into ZM with this username to migrate before using it with the ES. If that doesn't work, please configure a new user for the ES");
        return 0;
      }

      my $scheme = substr( $state->{Password}, 0, 1 );
      if ( $scheme eq '*' ) {    # mysql decode
        main::Debug(2, 'Comparing using mysql hash');
        if ( !main::try_use('Crypt::MySQL qw(password password41)') ) {
          main::Fatal('Crypt::MySQL  missing, cannot validate password');
          return 0;
        }
        my $encryptedPassword = password41($p);
        return $state->{Password} eq $encryptedPassword;
      } else {                     # try bcrypt
        if ( !main::try_use('Crypt::Eksblowfish::Bcrypt') ) {
          main::Fatal('Crypt::Eksblowfish::Bcrypt missing, cannot validate password');
          return 0;
        }
        my $saved_pass = $state->{Password};

        # perl bcrypt libs can't handle $2b$ or $2y$
        $saved_pass =~ s/^\$2.\$/\$2a\$/;
        my $new_hash = Crypt::Eksblowfish::Bcrypt::bcrypt( $p, $saved_pass );
        main::Debug(2, "Comparing using bcrypt");
        return $new_hash eq $saved_pass;
      }
    } else {
      return 0;
    }

  } else {
    # admin category
    main::Debug(1, 'Detected escontrol interface auth');
    return ( $p eq $escontrol_config{password} )
      && ($escontrol_config{enabled});
  }
}

sub processIncomingMessage {
  my ( $conn, $msg ) = @_;

  my $json_string;
  eval { $json_string = decode_json($msg); };
  if ($@) {
    main::Error("Failed decoding json in processIncomingMessage: $@");
    my $str = encode_json(
      { event  => 'malformed',
        type   => '',
        status => 'Fail',
        reason => 'BADJSON'
      }
    );
    eval { $conn->send_utf8($str); };
    main::Error("Error sending BADJSON: $@") if $@;
    return;
  }

  my $data = $json_string->{data};

  # This event type is when a command related to push notification is received
  if (( $json_string->{event} eq 'push' ) && !$fcm_config{enabled}) {
    my $str = encode_json(
      { event  => 'push',
        type   => '',
        status => 'Fail',
        reason => 'PUSHDISABLED'
      }
    );
    eval { $conn->send_utf8($str); };
    main::Error("Error sending PUSHDISABLED: $@") if $@;
    return;
  } elsif ($json_string->{event} eq 'escontrol') {
    if ( !$escontrol_config{enabled} ) {
      my $str = encode_json(
        { event  => 'escontrol',
          type   => '',
          status => 'Fail',
          reason => 'ESCONTROLDISABLED'
        }
      );
      eval { $conn->send_utf8($str); };
      main::Error("Error sending ESCONTROLDISABLED: $@") if $@;
      return;
    }
    processEsControlCommand($json_string, $conn);
    return;
  }

#-----------------------------------------------------------------------------------
# "push" event processing
#-----------------------------------------------------------------------------------
  elsif ( ( $json_string->{event} eq 'push' ) && $fcm_config{enabled} ) {

# sets the unread event count of events for a specific connection
# the server keeps a tab of # of events it pushes out per connection
# but won't know when the client has read them, so the client call tell the server
# using this message
    if ( $data->{type} eq 'badge' ) {
      main::Debug(2, 'badge command received');
      foreach (@main::active_connections) {
        if (
          (    ( exists $_->{conn} )
            && ( $_->{conn}->ip() eq $conn->ip() )
            && ( $_->{conn}->port() eq $conn->port() )
          )
          || ( $_->{token} eq $json_string->{token} )
          )
        {
          $_->{badge} = $data->{badge};
          main::Debug(2, 'badge match reset to ' . $_->{badge});
        }
      }
      return;
    }

    # This sub type is when a device token is registered
    if ( $data->{type} eq 'token' ) {
      if (!defined($data->{token}) || ($data->{token} eq '')) {
        main::Debug(2, 'Ignoring token command, I got '.encode_json($json_string));
        return;
      }
      # a token must have a platform
      if ( !$data->{platform} ) {
        my $str = encode_json(
          { event  => 'push',
            type   => 'token',
            status => 'Fail',
            reason => 'MISSINGPLATFORM'
          }
        );
        eval { $conn->send_utf8($str); };
        main::Error("Error sending MISSINGPLATFORM: $@") if $@;
        return;
      }

      my $token_matched = 0;
      my $stored_invocations = undef;
      my $stored_last_sent = undef;

      foreach (@main::active_connections) {
        if ($_->{token} eq $data->{token}) {
          if (
            ( !exists $_->{conn} )
            || ( $_->{conn}->ip() ne $conn->ip()
              || $_->{conn}->port() ne $conn->port() )
            )
          {
            my $existing_token = substr( $_->{token}, -10 );
            my $new_token = substr( $data->{token}, -10 );
            my $existing_conn = $_->{conn} ? $_->{conn}->ip().':'.$_->{conn}->port() : 'undefined';
            my $new_conn = $conn ? $conn->ip().':'.$conn->port() : 'undefined';

            main::Debug(2, "JOB: new token matched existing token: ($new_token <==> $existing_token) but connection did not ($new_conn <==> $existing_conn)");
            main::Debug(1, 'JOB: Duplicate token found: marking ...' . substr( $_->{token}, -10 ) . ' to be deleted');

            $_->{state} = PENDING_DELETE;
            $stored_invocations = $_->{invocations};
            $stored_last_sent = $_->{last_sent};
          } else {
            main::Debug(2, 'JOB: token matched, updating entry in active connections');
            $_->{invocations} = $stored_invocations if defined($stored_invocations);
            $_->{last_sent} = $stored_last_sent if defined($stored_last_sent);
            $_->{type}     = FCM;
            $_->{platform} = $data->{platform};
            $_->{monlist} = $data->{monlist} if isValidMonIntList($data->{monlist});
            $_->{intlist} = $data->{intlist} if isValidMonIntList($data->{intlist});
            $_->{pushstate} = $data->{state};
            main::Debug(1, 'JOB: Storing token ...'
                . substr( $_->{token}, -10 )
                . ',monlist:'
                . $_->{monlist}
                . ',intlist:'
                . $_->{intlist}
                . ',pushstate:'
                . $_->{pushstate} . "\n");
            my ( $emonlist, $eintlist ) = saveFCMTokens(
              $_->{token},    $_->{monlist}, $_->{intlist},
              $_->{platform}, $_->{pushstate}, $_->{invocations}, $_->{appversion}
            );
            $_->{monlist} = $emonlist;
            $_->{intlist} = $eintlist;
          }
        }
        elsif ( ( exists $_->{conn} )
          && ( $_->{conn}->ip() eq $conn->ip() )
          && ( $_->{conn}->port() eq $conn->port() )
          && ( $_->{token} ne $data->{token} ) )
        {
          my $existing_token = substr( $_->{token}, -10 );
          my $new_token = substr( $data->{token}, -10 );
          my $existing_conn = $_->{conn} ? $_->{conn}->ip().':'.$_->{conn}->port() : 'undefined';
          my $new_conn = $conn ? $conn->ip().':'.$conn->port() : 'undefined';

          main::Debug(2, "JOB: connection matched ($new_conn <==> $existing_conn) but token did not ($new_token <==> $existing_token). first registration?");

          $_->{type}     = FCM;
          $_->{token}    = $data->{token};
          $_->{platform} = $data->{platform};
          $_->{monlist}  = $data->{monlist} if isValidMonIntList($data->{monlist});
          $_->{intlist}  = $data->{intlist} if isValidMonIntList($data->{intlist});
          $_->{pushstate} = $data->{state};
          $_->{invocations} = defined ($stored_invocations) ? $stored_invocations:{count=>0, at=>(localtime)[4]};
          main::Debug(1, 'JOB: Storing token ...'
              . substr( $_->{token}, -10 )
              . ',monlist:'
              . $_->{monlist}
              . ',intlist:'
              . $_->{intlist}
              . ',pushstate:'
              . $_->{pushstate} . "\n");

          my ( $emonlist, $eintlist ) = saveFCMTokens(
            $_->{token},    $_->{monlist}, $_->{intlist},
            $_->{platform}, $_->{pushstate}, $_->{invocations}, $_->{appversion}
          );
          $_->{monlist} = $emonlist;
          $_->{intlist} = $eintlist;
        }
      }
    }
  }    # event = push
  #-----------------------------------------------------------------------------------
  # "control" event processing
  #-----------------------------------------------------------------------------------
  elsif ($json_string->{event} eq 'control') {
    if ( $data->{type} eq 'filter' ) {
      if ( !exists( $data->{monlist} ) ) {
        my $str = encode_json(
          { event  => 'control',
            type   => 'filter',
            status => 'Fail',
            reason => 'MISSINGMONITORLIST'
          }
        );
        eval { $conn->send_utf8($str); };
        main::Error("Error sending MISSINGMONITORLIST: $@") if $@;
        return;
      }
      if ( !exists( $data->{intlist} ) ) {
        my $str = encode_json(
          { event  => 'control',
            type   => 'filter',
            status => 'Fail',
            reason => 'MISSINGINTERVALLIST'
          }
        );
        eval { $conn->send_utf8($str); };
        main::Error("Error sending MISSINGINTERVALLIST: $@") if $@;
        return;
      }
      foreach (@main::active_connections) {
        if ( ( exists $_->{conn} )
          && ( $_->{conn}->ip() eq $conn->ip() )
          && ( $_->{conn}->port() eq $conn->port() ) )
        {
          $_->{monlist} = $data->{monlist};
          $_->{intlist} = $data->{intlist};
          main::Debug(2, 'Contrl: Storing token ...'
              . substr( $_->{token}, -10 )
              . ',monlist:'
              . $_->{monlist}
              . ',intlist:'
              . $_->{intlist}
              . ',pushstate:'
              . $_->{pushstate} . "\n");
          saveFCMTokens(
            $_->{token},    $_->{monlist}, $_->{intlist},
            $_->{platform}, $_->{pushstate}, $_->{invocations}, $_->{appversion}
          );
        }
      } # end foreach active_connections
    } elsif ( $data->{type} eq 'version' ) {
      foreach (@main::active_connections) {
        if ( ( exists $_->{conn} )
          && ( $_->{conn}->ip() eq $conn->ip() )
          && ( $_->{conn}->port() eq $conn->port() ) )
        {
          my $str = encode_json(
            { event   => 'control',
              type    => 'version',
              status  => 'Success',
              reason  => '',
              version => $main::app_version
            }
          );
          eval { $_->{conn}->send_utf8($str); };
          if ($@) {
            main::Error("Error sending version: $@");
          }
        }
      } # end foreach active_connections
    } # end if daa->type
  }    # event = control

#-----------------------------------------------------------------------------------
# "auth" event processing
#-----------------------------------------------------------------------------------
# This event type is when a command related to authorization is sent
  elsif ( $json_string->{event} eq 'auth' ) {
    my $uname      = $data->{user};
    my $pwd        = $data->{password};
    my $appversion = $data->{appversion};
    my $category   = exists($json_string->{category}) ? $json_string->{category} : 'normal';

    if ( $category ne 'normal' && $category ne 'escontrol' ) {
      main::Debug(1, "Auth category $category is invalid. Resetting it to 'normal'");
      $category = 'normal';
    }

    my $monlist = exists($data->{monlist}) ? $data->{monlist} : '';
    my $intlist = exists($data->{intlist}) ? $data->{intlist} : '';

    foreach (@main::active_connections) {
      if ( ( exists $_->{conn} )
        && ( $_->{conn}->ip() eq $conn->ip() )
        && ( $_->{conn}->port() eq $conn->port() ) )

        # && ( $_->{state} == PENDING_AUTH ) ) # lets allow multiple auths
      {
        if ( !validateAuth( $uname, $pwd, $category ) ) {
          # bad username or password, so reject and mark for deletion
          my $str = encode_json(
            { event  => 'auth',
              type   => '',
              status => 'Fail',
              reason => (( $category eq 'escontrol' && !$escontrol_config{enabled} ) ? 'ESCONTROLDISABLED' : 'BADAUTH')
            }
          );
          eval { $_->{conn}->send_utf8($str); };
          main::Error("Error sending BADAUTH: $@") if $@;
          main::Debug(1, 'marking for deletion - bad authentication provided by '.$_->{conn}->ip());
          $_->{state} = PENDING_DELETE;
        } else {

          # all good, connection auth was valid
          $_->{category}   = $category;
          $_->{appversion} = $appversion;
          $_->{state}      = VALID_CONNECTION;
          $_->{monlist}    = $monlist;
          $_->{intlist}    = $intlist;
          $_->{token}      = '';
          my $str = encode_json(
            { event   => 'auth',
              type    => '',
              status  => 'Success',
              reason  => '',
              version => $main::app_version
            }
          );
          eval { $_->{conn}->send_utf8($str); };
          main::Error("Error sending auth success: $@") if $@;
          main::Info( "Correct authentication provided by " . $_->{conn}->ip() );
        } # end if validateAuth
      } # end if this is the right connection
    } # end foreach active connection
  }    # event = auth
  else {
    my $str = encode_json(
      { event  => $json_string->{event},
        type   => '',
        status => 'Fail',
        reason => 'NOTSUPPORTED'
      }
    );
    eval { $_->{conn}->send_utf8($str); };
    main::Error("Error sending NOTSUPPORTED: $@") if $@;
  }
}

1;
