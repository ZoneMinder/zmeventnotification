package ZmEventNotification::FCM;
use strict;
use warnings;
use Exporter 'import';
use JSON;
use MIME::Base64;
use URI::Escape;
use POSIX qw(strftime);
use Time::HiRes qw(gettimeofday);
use ZmEventNotification::Constants qw(:all);
use ZmEventNotification::Config qw(:all);
use ZmEventNotification::Util qw(uniq rsplit buildPictureUrl stripFrameMatchType);

our @EXPORT_OK = qw(
  deleteFCMToken get_google_access_token
  sendOverFCM sendOverFCMV1 sendOverFCMLegacy
  migrateTokens initFCMTokens saveFCMTokens
);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

sub _check_monthly_limit {
  my $obj = shift;
  my $curmonth = (localtime)[4];
  if (defined($obj->{invocations})) {
    my $month = $obj->{invocations}->{at};
    if ($curmonth != $month) {
      $obj->{invocations}->{count} = 0;
      main::printDebug('Resetting counters for token...' . substr($obj->{token}, -10) . ' as month changed', 1);
    }
    if ($obj->{invocations}->{count} > DEFAULT_MAX_FCM_PER_MONTH_PER_TOKEN) {
      main::printError('Exceeded message count of ' .
        DEFAULT_MAX_FCM_PER_MONTH_PER_TOKEN . ' for this month, for token...' .
        substr($obj->{token}, -10) . ', not sending FCM');
      return 1;
    }
  }
  return 0;
}

sub _base64url_encode {
  my $data = shift;
  my $encoded = encode_base64($data, '');
  $encoded =~ s/\+/\-/g;
  $encoded =~ s/\//_/g;
  $encoded =~ s/=+$//;
  $encoded =~ s/\n//g;
  return $encoded;
}


sub deleteFCMToken {
  my $dtoken = shift;
  main::printDebug( 'DeleteToken called with ...' . substr( $dtoken, -10 ), 2 );
  return if !-f $fcm_config{token_file};
  open( my $fh, '<', $fcm_config{token_file} ) or main::Fatal("Error opening $fcm_config{token_file}: $!");
  my %tokens_data;
  my $hr;
  my $data = do { local $/ = undef; <$fh> };
  close($fh);
  eval { $hr = decode_json($data); };

  if ($@) {
    main::printError("Could not delete token from file: $!");
    return;
  } else {
    %tokens_data = %$hr;
    delete $tokens_data{tokens}->{$dtoken}
      if exists( $tokens_data{tokens}->{$dtoken} );
    open( my $fh, '>', $fcm_config{token_file} )
      or main::printError("Error writing tokens file: $!");
    my $json = encode_json( \%tokens_data );
    print $fh $json;
    close($fh);
  }

  foreach (@main::active_connections) {
    next if ( $_ eq '' || $_->{token} ne $dtoken );
    $_->{state} = INVALID_CONNECTION;
  }
}

sub get_google_access_token {
  my $key_file = shift;

  if (time() < $fcm_config{cached_access_token_expiry}) {
      return $fcm_config{cached_access_token};
  }

  if ( !main::try_use('Crypt::OpenSSL::RSA') ) {
    main::printError("Crypt::OpenSSL::RSA is required for Service Account Auth");
    return undef;
  }

  local $/;
  open( my $fh, '<', $key_file ) or do {
    main::printError("Could not open service account file $key_file: $!");
    return undef;
  };
  my $json_text = <$fh>;
  close($fh);

  my $data = decode_json($json_text);
  my $client_email = $data->{client_email};
  my $private_key_pem = $data->{private_key};
  my $token_uri = $data->{token_uri} || 'https://oauth2.googleapis.com/token';

  my $now = time();
  my $exp = $now + 3600;

  my $header = {
    alg => 'RS256',
    typ => 'JWT'
  };

  my $claim = {
    iss => $client_email,
    scope => 'https://www.googleapis.com/auth/firebase.messaging',
    aud => $token_uri,
    exp => $exp,
    iat => $now
  };

  my $encoded_header = _base64url_encode(encode_json($header));
  my $encoded_claim  = _base64url_encode(encode_json($claim));
  my $payload = "$encoded_header.$encoded_claim";

  my $rsa = Crypt::OpenSSL::RSA->new_private_key($private_key_pem);
  $rsa->use_sha256_hash();
  my $encoded_signature = _base64url_encode($rsa->sign($payload));

  my $jwt = "$payload.$encoded_signature";

  my $ua = LWP::UserAgent->new();
  my $req = HTTP::Request->new(POST => $token_uri);
  $req->header('Content-Type' => 'application/x-www-form-urlencoded');
  $req->content("grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=$jwt");

  my $res = $ua->request($req);

  if ($res->is_success) {
    my $token_data = decode_json($res->decoded_content);
    $fcm_config{cached_access_token} = $token_data->{access_token};
    $fcm_config{cached_access_token_expiry} = time() + $token_data->{expires_in} - 60;
    return $fcm_config{cached_access_token};
  } else {
    main::printError("Failed to get access token: " . $res->status_line . " " . $res->decoded_content);
    return undef;
  }
}

sub sendOverFCM {
  if ($fcm_config{use_v1}) {
    sendOverFCMV1( shift, shift, shift, shift );
  } else {
    sendOverFCMLegacy( shift, shift, shift, shift );
  }
}

sub sendOverFCMV1 {
  my $alarm      = shift;
  my $obj        = shift;
  my $event_type = shift;
  my $resCode    = shift;
  my $key;
  my $uri;

  if ($fcm_config{service_account_file}) {
      main::printDebug("fcmv1: Using direct FCM with service account file: $fcm_config{service_account_file}", 2);

      my $access_token = get_google_access_token($fcm_config{service_account_file});
      if (!$access_token) {
          main::printError("fcmv1: Failed to get access token from service account file. Push notification aborted.");
          return;
      }

      $key = "Bearer $access_token";

      local $/;
      my $fh;
      if (!open( $fh, '<', $fcm_config{service_account_file} )) {
          main::printError("fcmv1: Cannot open service account file $fcm_config{service_account_file}: $!. Push notification aborted.");
          return;
      }
      my $json_text = <$fh>;
      close($fh);

      my $data = decode_json($json_text);
      my $project_id = $data->{project_id};
      if (!$project_id) {
          main::printError("fcmv1: No project_id found in service account file. Push notification aborted.");
          return;
      }

      $uri = "https://fcm.googleapis.com/v1/projects/$project_id/messages:send";
      main::printDebug("fcmv1: Using direct FCM URL: $uri", 2);

  } else {
      main::printDebug("fcmv1: Using shared proxy mode (zmNinja)", 2);
      $key = $fcm_config{v1_key};
      $uri = $fcm_config{v1_url};
      main::printDebug("fcmv1: Using proxy URL: $uri", 2);
  }

  my $mid   = $alarm->{MonitorId};
  my $eid   = $alarm->{EventId};
  my $mname = $alarm->{Name};

  return if _check_monthly_limit($obj);

  my $pic = buildPictureUrl($eid, $alarm->{Cause}, $resCode, 'fcmv1');
  $alarm->{Cause} = stripFrameMatchType($alarm->{Cause});

  my $body = $alarm->{Cause};
  $body .= ' ended' if $event_type eq 'event_end';
  $body .= ' at ' . strftime($fcm_config{date_format}, localtime);

  my $badge = $obj->{badge} + 1;
  my $count = defined($obj->{invocations})?$obj->{invocations}->{count}+1:0;

  print main::WRITER 'fcm_notification--TYPE--' . $obj->{token} . '--SPLIT--' . $badge
                .'--SPLIT--' . $count .'--SPLIT--'.(localtime)[4]. "\n";

  my $title = $mname . ' Alarm';
  $title = $title . ' (' . $eid . ')' if $notify_config{tag_alarm_event_id};
  $title = 'Ended:' . $title          if $event_type eq 'event_end';

  my $message_v2;

  if ($fcm_config{service_account_file}) {
      main::printDebug("fcmv1: Building Google FCM v1 API format", 2);

      $message_v2 = {
        message => {
          token => $obj->{token},
          notification => {
            title => $title,
            body  => $body
          },
          data => {
            mid => "$mid",
            eid => "$eid",
            notification_foreground => 'true'
          }
        }
      };

      if ( $notify_config{picture_url} && $notify_config{include_picture} ) {
        $message_v2->{message}->{notification}->{image} = $pic;
      }

      if ($obj->{platform} eq 'android') {
        $message_v2->{message}->{android} = {
          priority => $fcm_config{android_priority},
          notification => {
            icon => 'ic_stat_notification',
            sound => 'default'
          }
        };
        $message_v2->{message}->{android}->{ttl} = $fcm_config{android_ttl} . 's' if defined($fcm_config{android_ttl});
        $message_v2->{message}->{android}->{notification}->{tag} = 'zmninjapush' if $fcm_config{replace_push_messages};
        if (defined ($obj->{appversion}) && ($obj->{appversion} ne 'unknown')) {
          main::printDebug('fcmv1: setting android channel to zmninja', 2);
          $message_v2->{message}->{android}->{notification}->{channel_id} = 'zmninja';
        } else {
          main::printDebug('fcmv1: legacy android client, NOT setting channel', 2);
        }
      } elsif ($obj->{platform} eq 'ios') {
        $message_v2->{message}->{apns} = {
          payload => {
            aps => {
              alert => {
                title => $title,
                body => $body
              },
              badge => int($badge),
              sound => 'default',
              'thread-id' => 'zmninja_alarm'
            }
          },
          headers => {
            'apns-priority' => '10',
            'apns-push-type' => 'alert'
          }
        };
        $message_v2->{message}->{apns}->{headers}->{'apns-collapse-id'} = 'zmninjapush' if $fcm_config{replace_push_messages};
      } else {
        main::printDebug('fcmv1: Unknown platform '.$obj->{platform}, 2);
      }

  } else {
      main::printDebug("fcmv1: Building proxy format", 2);

      $message_v2 = {
        token => $obj->{token},
        title => $title,
        body  => $body,
        sound => 'default',
        badge => int($badge),
        log_message_id => $fcm_config{log_message_id},
        data  => {
          mid                     => $mid,
          eid                     => $eid,
          notification_foreground => 'true'
        }
      };

      if ($obj->{platform} eq 'android') {
        $message_v2->{android} = {
          icon     => 'ic_stat_notification',
          priority => $fcm_config{android_priority}
        };
        $message_v2->{android}->{ttl} = $fcm_config{android_ttl} if defined($fcm_config{android_ttl});
        $message_v2->{android}->{tag} = 'zmninjapush' if $fcm_config{replace_push_messages};
        if (defined ($obj->{appversion}) && ($obj->{appversion} ne 'unknown')) {
          main::printDebug('setting channel to zmninja', 2);
          $message_v2->{android}->{channel} = 'zmninja';
        } else {
          main::printDebug('legacy client, NOT setting channel to zmninja', 2);
        }
      } elsif ($obj->{platform} eq 'ios') {
        $message_v2->{ios} = {
          thread_id=>'zmninja_alarm',
          headers => {
            'apns-priority' => '10' ,
            'apns-push-type'=>'alert',
          }
        };
        $message_v2->{ios}->{headers}->{'apns-collapse-id'} = 'zmninjapush' if ($fcm_config{replace_push_messages});
      } else {
        main::printDebug('Unknown platform '.$obj->{platform}, 2);
      }

      if ($fcm_config{log_raw_message}) {
        $message_v2->{log_raw_message} = 'yes';
        main::printDebug("The server cloud function at $uri will log your full message. Please ONLY USE THIS FOR DEBUGGING with me author and turn off later", 2);
      }

      if ( $notify_config{picture_url} && $notify_config{include_picture} ) {
        $message_v2->{image_url} = $pic;
      }
  }
  my $json = encode_json($message_v2);
  my $djson = $json;
  $djson =~ s/pass(word)?=(.*?)($|&|})/pass$1=xxx$3/g;

  main::printDebug(
    "fcmv1: Final JSON using FCMV1 being sent is: $djson to token: ..."
      . substr( $obj->{token}, -6 ),
    2
  );
  my $req = HTTP::Request->new('POST', $uri);
  $req->header(
    'Content-Type'  => 'application/json',
    'Authorization' => $key
  );

  $req->content($json);
  my $lwp = LWP::UserAgent->new(%main::ssl_push_opts);
  my $res = $lwp->request($req);

  if ( $res->is_success ) {
    $main::pcnt++;
    main::printDebug(
      'fcmv1: FCM push message returned a 200 with body ' . $res->decoded_content, 1 );
  } else {
    main::printDebug('fcmv1: FCM push message error '.$res->decoded_content,1);
    if ( (index( $res->decoded_content, 'not a valid FCM' ) != -1) ||
          (index( $res->decoded_content, 'entity was not found') != -1)) {
      main::printDebug('fcmv1: Removing this token as FCM doesn\'t recognize it', 1);
      deleteFCMToken($obj->{token});
    }
  }

  if ( ($obj->{state} == VALID_CONNECTION) && exists $obj->{conn} ) {
    my $sup_str = encode_json(
      { event         => 'alarm',
        type          => '',
        status        => 'Success',
        supplementary => 'true',
        events        => [$alarm]
      }
    );
    print main::WRITER 'message--TYPE--' . $obj->{id} . '--SPLIT--' . $sup_str . "\n";
  }
}

sub sendOverFCMLegacy {
  main::printDebug("Using Legacy");
  use constant NINJA_API_KEY =>
    'AAAApYcZ0mA:APA91bG71SfBuYIaWHJorjmBQB3cAN7OMT7bAxKuV3ByJ4JiIGumG6cQw0Bo6_fHGaWoo4Bl-SlCdxbivTv5Z-2XPf0m86wsebNIG15pyUHojzmRvJKySNwfAHs7sprTGsA_SIR_H43h';

  my $alarm      = shift;
  my $obj        = shift;
  my $event_type = shift;
  my $resCode    = shift;

  my $mid   = $alarm->{MonitorId};
  my $eid   = $alarm->{EventId};
  my $mname = $alarm->{Name};

  return if _check_monthly_limit($obj);

  my $pic = buildPictureUrl($eid, $alarm->{Cause}, $resCode, 'legacy');
  $alarm->{Cause} = stripFrameMatchType($alarm->{Cause});

  my $body = $alarm->{Cause};
  $body .= ' ended' if $event_type eq 'event_end';
  $body .= ' at ' . strftime($fcm_config{date_format}, localtime);

  my $badge = $obj->{badge} + 1;
  my $count = defined($obj->{invocations})?$obj->{invocations}->{count}+1:0;
  my $at = (localtime)[4];

  print main::WRITER 'fcm_notification--TYPE--' . $obj->{token} . '--SPLIT--' . $badge
                .'--SPLIT--' . $count .'--SPLIT--' . $at . "\n";

  my $key   = 'key=' . NINJA_API_KEY;
  my $title = $mname . ' Alarm';
  $title = $title . ' (' . $eid . ')' if $notify_config{tag_alarm_event_id};
  $title = 'Ended:' . $title          if $event_type eq 'event_end';

  my $ios_message = {
    to           => $obj->{token},
    notification => {
      title => $title,
      body  => $body,
      sound => 'default',
      badge => $badge,
    },
    data => {
      notification_foreground => 'true',
      myMessageId             => $main::notId,
      mid                     => $mid,
      eid                     => $eid,
      summaryText             => $eid,
      apns                    => {
        payload => {
          aps => {
            sound             => 'default',
            content_available => 1
          }
        }
      }
    }
  };

  my $android_message = {
    to           => $obj->{token},
    notification => {
      title              => $title,
      android_channel_id => 'zmninja',
      icon               => 'ic_stat_notification',
      body               => $body,
      sound              => 'default',
      badge              => $badge,
    },
    data => {
      title       => $title,
      message     => $body,
      style       => 'inbox',
      myMessageId => $main::notId,
      icon        => 'ic_stat_notification',
      mid         => $mid,
      eid         => $eid,
      badge       => $obj->{badge},
      priority    => 1
    }
  };

  if (defined($obj->{appversion}) && ($obj->{appversion} ne 'unknown')) {
    main::printDebug('setting channel to zmninja', 2);
    $android_message->{notification}->{android_channel_id} = 'zmninja';
    $android_message->{data}->{channel} = 'zmninja';
  } else {
    main::printDebug('legacy client, NOT setting channel to zmninja', 2);
  }
  if ($notify_config{picture_url} && $notify_config{include_picture}) {
    $ios_message->{mutable_content} = \1;
    $ios_message->{data}->{image_url_jpg} = $pic;
    $android_message->{notification}->{image} = $pic;
    $android_message->{data}->{style}         = 'picture';
    $android_message->{data}->{picture}       = $pic;
    $android_message->{data}->{summaryText}   = 'alarmed image';
  }

  my $json;
  if ($obj->{platform} eq 'ios') {
    $json = encode_json($ios_message);
  } else {
    $json  = encode_json($android_message);
    $main::notId = ( $main::notId + 1 ) % 100000;
  }

  my $djson = $json;
  $djson =~ s/pass(word)?=(.*?)($|&)/pass$1=xxx$3/g;

  main::printDebug(
    "legacy: Final JSON being sent is: $djson to token: ..."
      . substr( $obj->{token}, -6 ),
    2
  );
  my $uri = 'https://fcm.googleapis.com/fcm/send';
  my $req = HTTP::Request->new('POST', $uri);
  $req->header(
    'Content-Type'  => 'application/json',
    'Authorization' => $key
  );
  $req->content($json);
  my $lwp = LWP::UserAgent->new(%main::ssl_push_opts);
  my $res = $lwp->request($req);

  if ($res->is_success) {
    $main::pcnt++;
    my $msg = $res->decoded_content;
    main::printDebug('FCM push message returned a 200 with body '.$res->content, 1);
    my $json_string;
    eval { $json_string = decode_json($msg); };
    if ($@) {
      main::Error("Failed decoding sendFCM Response: $@");
      return;
    }
    if ( $json_string->{failure} eq 1 ) {
      my $reason = $json_string->{results}[0]->{error};
      main::Error('Error sending FCM for token:' . $obj->{token});
      main::Error('Error value =' . $reason);
      if ( $reason eq 'NotRegistered'
        || $reason eq 'InvalidRegistration' )
      {
        main::printDebug('Removing this token as FCM doesn\'t recognize it', 1);
        deleteFCMToken($obj->{token});
      }
    } # end if failure
  } else {
    main::printError('FCM push message Error:' . $res->status_line);
  }

  if ($obj->{state} == VALID_CONNECTION && exists $obj->{conn}) {
    my $sup_str = encode_json(
      { event         => 'alarm',
        type          => '',
        status        => 'Success',
        supplementary => 'true',
        events        => [$alarm]
      }
    );
    print main::WRITER 'message--TYPE--' . $obj->{id} . '--SPLIT--' . $sup_str . "\n";
  }
}

sub migrateTokens {
  my %tokens;
  $tokens{tokens} = {};
  {
    open(my $fh, '<', $fcm_config{token_file}) or main::Fatal("Error opening $fcm_config{token_file}: $!");
    chomp(my @lines = <$fh>);
    close($fh);

    foreach (uniq(@lines)) {
      next if $_ eq '';
      my ( $token, $monlist, $intlist, $platform, $pushstate ) =
      rsplit( qr/:/, $_, 5 );
      $tokens{tokens}->{$token} = {
        monlist   => $monlist,
        intlist   => $intlist,
        platform  => $platform,
        pushstate => $pushstate,
        invocations => {count=>0, at=>(localtime)[4]}
      };
    }
  }
  my $json = encode_json(\%tokens);

  open(my $fh, '>', $fcm_config{token_file})
    or main::Fatal("Error creating new migrated file: $!");
  print $fh $json;
  close($fh);
}

sub initFCMTokens {
  main::printDebug('Initializing FCM tokens...', 1);
  if (!-f $fcm_config{token_file}) {
    open(my $foh, '>', $fcm_config{token_file}) or main::Fatal("Error opening $fcm_config{token_file}: $!");
    main::printDebug('Creating ' . $fcm_config{token_file}, 1);
    print $foh '{"tokens":{}}';
    close($foh);
  }

  open(my $fh, '<', $fcm_config{token_file}) or main::Fatal("Error opening $fcm_config{token_file}: $!");
  my %tokens_data;
  my $hr;
  my $data = do { local $/ = undef; <$fh> };
  close ($fh);
  eval { $hr = decode_json($data); };
  if ($@) {
    main::printInfo('tokens is not JSON, migrating format...');
    migrateTokens();
    open(my $fh, '<', $fcm_config{token_file}) or main::Fatal("Error opening $fcm_config{token_file}: $!");
    my $data = do { local $/ = undef; <$fh> };
    close ($fh);
    eval { $hr = decode_json($data); };
    if ($@) {
      main::Fatal("Migration to JSON file failed: $!");
    } else {
      %tokens_data = %$hr;
    }
  } else {
    %tokens_data = %$hr;
  }

  %main::fcm_tokens_map = %tokens_data;
  @main::active_connections = ();
  foreach my $key ( keys %{ $tokens_data{tokens} } ) {
    my $token      = $key;
    my $monlist    = $tokens_data{tokens}->{$key}->{monlist};
    my $intlist    = $tokens_data{tokens}->{$key}->{intlist};
    my $platform   = $tokens_data{tokens}->{$key}->{platform};
    my $pushstate  = $tokens_data{tokens}->{$key}->{pushstate};
    my $appversion = $tokens_data{tokens}->{$key}->{appversion};
    my $invocations = defined($tokens_data{tokens}->{$key}->{invocations}) ?
      $tokens_data{tokens}->{$key}->{invocations} : {count=>0, at=>(localtime)[4]};

    push @main::active_connections,
      {
      type         => FCM,
      id           => int scalar gettimeofday(),
      token        => $token,
      state        => INVALID_CONNECTION,
      time         => time(),
      badge        => 0,
      monlist      => $monlist,
      intlist      => $intlist,
      last_sent    => {},
      platform     => $platform,
      extra_fields => '',
      pushstate    => $pushstate,
      appversion   => $appversion,
      invocations  => $invocations
      };
  } # end foreach token
}

sub saveFCMTokens {
  return if !$fcm_config{enabled};
  my $stoken     = shift;
  my $smonlist   = shift;
  my $sintlist   = shift;
  my $splatform  = shift;
  my $spushstate = shift;
  my $invocations = shift;
  my $appversion = shift || 'unknown';

  $invocations = {count=>0, at=>(localtime)[4]} if !defined($invocations);

  if ($stoken eq '') {
    main::printDebug('Not saving, no token. Desktop?', 2);
    return;
  }

  if ($spushstate eq '') {
    $spushstate = 'enabled';
    main::printDebug(
      'Overriding token state, setting to enabled as I got a null with a valid token',
      1
    );
  }

  main::printDebug(
    "SaveTokens called with:monlist=$smonlist, intlist=$sintlist, platform=$splatform, push=$spushstate",
    2
  );

  open(my $fh, '<', $fcm_config{token_file}) || main::Fatal('Cannot open for read '.$fcm_config{token_file});
  my $data = do { local $/ = undef; <$fh> };
  close($fh);

  my $tokens_data;
  eval { $tokens_data = decode_json($data); };
  if ($@) {
    main::printError("Could not parse token file: $!");
    return;
  }
  $$tokens_data{tokens}->{$stoken}->{monlist} = $smonlist if $smonlist ne '-1';
  $$tokens_data{tokens}->{$stoken}->{intlist} = $sintlist if $sintlist ne '-1';
  $$tokens_data{tokens}->{$stoken}->{platform}  = $splatform;
  $$tokens_data{tokens}->{$stoken}->{pushstate} = $spushstate;
  $$tokens_data{tokens}->{$stoken}->{invocations} = $invocations;
  $$tokens_data{tokens}->{$stoken}->{appversion} = $appversion;

  open($fh, '>', $fcm_config{token_file})
    or main::printError("Error writing tokens file $fcm_config{token_file}: $!");
  print $fh encode_json($tokens_data);
  close($fh);
  return ( $smonlist, $sintlist );
}

1;
