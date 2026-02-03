package ZmEventNotification::HookProcessor;
use strict;
use warnings;
use Exporter 'import';
use JSON;
use POSIX qw(strftime);
use Time::HiRes qw(gettimeofday);
use ZmEventNotification::Constants qw(:all);
use ZmEventNotification::Config qw(:all);
use ZmEventNotification::Util qw(getConnectionIdentity isInList getInterval parseDetectResults buildPictureUrl stripFrameMatchType);
use ZmEventNotification::FCM qw(sendOverFCM);
use ZmEventNotification::MQTT qw(sendOverMQTTBroker);
use ZmEventNotification::Rules qw(isAllowedInRules);
use ZmEventNotification::DB qw(updateEventinZmDB getNotesFromEventDB tagEventObjects);
use ZmEventNotification::WebSocketHandler qw(getNotificationStatusEsControl);

our @EXPORT_OK = qw(
  processNewAlarmsInFork
  sendEvent
  isAllowedChannel
  shouldSendEventToConn
  sendOverWebSocket
);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

sub sendOverWebSocket {
  my $alarm      = shift;
  my $ac         = shift;
  my $event_type = shift;
  my $resCode    = shift;

  my $eid = $alarm->{EventId};

  if ( $notify_config{picture_url} && $notify_config{include_picture} ) {
    $alarm->{Picture} = buildPictureUrl($eid, $alarm->{Cause}, $resCode, 'websocket');
  }

  $alarm->{Cause} = stripFrameMatchType($alarm->{Cause});

  $alarm->{Cause} = 'End:'.$alarm->{Cause} if $event_type eq 'event_end';
  my $json = encode_json(
    { event  => 'alarm',
      type   => '',
      status => 'Success',
      events => [$alarm]
    }
  );
  main::Debug(2, 'Child: posting job to send out message to id:'
      . $ac->{id} . '->'
      . $ac->{conn}->ip() . ':'
      . $ac->{conn}->port());
  print main::WRITER 'message--TYPE--' . $ac->{id} . '--SPLIT--' . $json . "\n";
}

sub sendEvent {
  my $alarm      = shift;
  my $ac         = shift;
  my $event_type = shift;
  my $resCode    = shift;    # 0 = on_success, 1 = on_fail

  my $id   = $alarm->{MonitorId};
  my $name = $alarm->{Name};

  if ( ( !$notify_config{send_event_end_notification} ) && ( $event_type eq 'event_end' ) ) {
    main::Info(
      'Not sending event end notification as send_event_end_notification is no'
    );
    return;
  }

  if ( ( !$notify_config{send_event_start_notification} ) && ( $event_type eq 'event_start' ) ) {
    main::Info(
      'Not sending event start notification as send_event_start_notification is no'
    );
    return;
  }

  my $hook = $event_type eq 'event_start' ? $hooks_config{event_start_hook} : $hooks_config{event_end_hook};

  my $t   = gettimeofday;
  my $str = encode_json(
    { event  => 'alarm',
      type   => '',
      status => 'Success',
      events => [$alarm]
    }
  );

  if ( $ac->{type} == FCM
    && $ac->{pushstate} ne 'disabled'
    && $ac->{state} != PENDING_AUTH
    && $ac->{state} != PENDING_DELETE
    )
  {
    # only send if fcm is an allowed channel
    if ( isAllowedChannel( $event_type, 'fcm', $resCode )
      || !$hook
      || !$hooks_config{enabled} )
    {
      main::Info("Sending $event_type notification over FCM");
      sendOverFCM( $alarm, $ac, $event_type, $resCode );
    } else {
      main::Info(
        "Not sending over FCM as notify filters are on_success:$hooks_config{event_start_notify_on_hook_success} and on_fail:$hooks_config{event_end_notify_on_hook_fail}"
      );
    }
  } elsif ( $ac->{type} == WEB
    && $ac->{state} == VALID_CONNECTION
    && exists $ac->{conn} )
  {

    if ( isAllowedChannel( $event_type, 'web', $resCode )
      || !$hook
      || !$hooks_config{enabled} )
    {
      main::Info( "Sending $event_type notification for EID:"
          . $alarm->{EventId}
          . 'over web' );
      sendOverWebSocket( $alarm, $ac, $event_type, $resCode );
    } else {
      main::Info(
        "Not sending over Web as notify filters are on_success:$hooks_config{event_start_notify_on_hook_success} and on_fail:$hooks_config{event_start_notify_on_hook_fail}"
      );
    }

  } elsif ( $ac->{type} == MQTT ) {
    if ( isAllowedChannel( $event_type, 'mqtt', $resCode )
      || !$hook
      || !$hooks_config{enabled} )
    {
      main::Info( "Sending $event_type notification for EID:"
          . $alarm->{EventId}
          . ' over MQTT' );
      sendOverMQTTBroker( $alarm, $ac, $event_type, $resCode );
    } else {
      main::Info(
        "Not sending over MQTT as notify filters are on_success:$hooks_config{event_start_notify_on_hook_success} and on_fail:$hooks_config{event_start_notify_on_hook_fail}"
      );
    }
  }

  print main::WRITER 'timestamp--TYPE--'
    . $ac->{id}
    . '--SPLIT--'
    . $alarm->{MonitorId}
    . '--SPLIT--'
    . $t . "\n";

  main::Debug(2, 'child finished writing to parent');
}

sub isAllowedChannel {
  my $event_type = shift;
  my $channel    = shift;
  my $rescode    = shift;

  main::Debug(2, "isAllowedChannel: got type:$event_type resCode:$rescode");

  my $key;
  if ( $event_type eq 'event_start' ) {
    $key = $rescode == 0 ? 'event_start_notify_on_hook_success' : 'event_start_notify_on_hook_fail';
  } elsif ( $event_type eq 'event_end' ) {
    $key = $rescode == 0 ? 'event_end_notify_on_hook_success' : 'event_end_notify_on_hook_fail';
  } else {
    main::Error("Invalid event_type:$event_type sent to isAllowedChannel()");
    return 0;
  }

  my %allowed = map { $_ => 1 } split(/\s*,\s*/, lc($hooks_config{$key} // ''));
  return exists($allowed{$channel}) || exists($allowed{all});
}

sub shouldSendEventToConn {
  my $alarm  = shift;
  my $ac     = shift;
  my $retVal = 0;

  my $monlist   = $ac->{monlist};
  my $intlist   = $ac->{intlist};
  my $last_sent = $ac->{last_sent};

  if ($escontrol_config{enabled}) {
    my $id   = $alarm->{MonitorId};
    my $name = $alarm->{Name};
    if ( getNotificationStatusEsControl($id) == ESCONTROL_FORCE_NOTIFY ) {
      main::Debug(1, "ESCONTROL: Notifications are force enabled for Monitor:$name($id), returning true");
      return 1;
    }

    if ( getNotificationStatusEsControl($id) == ESCONTROL_FORCE_MUTE ) {
      main::Debug(1, "ESCONTROL: Notifications are muted for Monitor:$name($id), not sending");
      return 0;
    }
  }

  my $id     = getConnectionIdentity($ac);
  my $connId = $ac->{id};
  main::Debug(1, 'Checking alarm conditions for '.$id);

  if ( isInList( $monlist, $alarm->{MonitorId} ) ) {
    my $mint = getInterval( $intlist, $monlist, $alarm->{MonitorId} );
    if ( $last_sent->{ $alarm->{MonitorId} } ) {
      my $elapsed = time() - $last_sent->{ $alarm->{MonitorId} };
      if ( $elapsed >= $mint ) {
        main::Debug(1, 'Monitor '
            . $alarm->{MonitorId}
            . " event: should send out as  $elapsed is >= interval of $mint");
        $retVal = 1;
      } else {
        main::Debug(1, 'Monitor '
            . $alarm->{MonitorId}
            . " event: should NOT send this out as $elapsed is less than interval of $mint");
        $retVal = 0;
      }
    } else {
      main::Debug(1, 'Monitor '.$alarm->{MonitorId}.' event: last time not found, so should send');
      $retVal = 1;
    }
  } else {
    main::Debug(1, 'should NOT send alarm as Monitor '.$alarm->{MonitorId}.' is excluded');
    $retVal = 0;
  }

  return $retVal;
}

sub processNewAlarmsInFork {
  my $newEvent       = shift;
  my $alarm          = $newEvent->{Alarm};
  my $monitor        = $newEvent->{MonitorObj};
  my $mid            = $alarm->{MonitorId};
  my $eid            = $alarm->{EventId};
  my $mname          = $alarm->{MonitorName};
  my $doneProcessing = 0;

  my $hookResult      = 0;
  my $startHookResult = $hookResult;
  my $hookString = '';

  my $endProcessed = 0;

  my $start_time = time();

  while (!$doneProcessing and !$main::es_terminate) {

    my $now = time();
    if ( $now - $start_time > 3600 ) {
      main::Info('Thread alive for an hour, bailing...');
      $doneProcessing = 1;
    }

    if ( $alarm->{Start}->{State} eq 'pending' ) {
      if ( { map { $_ => 1 } split(',', $hooks_config{hook_skip_monitors} // '') }->{$mid} ) {
        main::Info("$mid is in hook skip list, not using hooks");
        $alarm->{Start}->{State} = 'ready';
        $hookResult = 0;
      } else {
        if ( $hooks_config{event_start_hook} && $hooks_config{enabled} ) {
          my $cmd =
              $hooks_config{event_start_hook} . ' '
            . $eid . ' '
            . $mid . ' "'
            . $alarm->{MonitorName} . '" "'
            . $alarm->{Start}->{Cause} . '"';

          if ($hooks_config{hook_pass_image_path}) {
            my $event = new ZoneMinder::Event($eid);
            $cmd = $cmd . ' "' . $event->Path() . '"';
            main::Debug(2, 'Adding event path:'
                . $event->Path()
                . ' to hook for image storage');
          }
          main::Debug(1, 'Invoking hook on event start:' . $cmd);

          if ( $cmd =~ /^(.*)$/ ) {
            $cmd = $1;
          }
          print main::WRITER "update_parallel_hooks--TYPE--add\n";
          my $res = `$cmd`;
          $hookResult = $? >> 8;

          print main::WRITER "update_parallel_hooks--TYPE--del\n";

          chomp($res);
          my ( $resTxt, $resJsonString ) = parseDetectResults($res);
          $hookResult = 1 if !$resTxt;
          $startHookResult = $hookResult;

          main::Debug(1, "hook start returned with text:$resTxt json:$resJsonString exit:$hookResult");

          if ($hooks_config{event_start_hook_notify_userscript}) {
            my $user_cmd =
                $hooks_config{event_start_hook_notify_userscript} . ' '
              . $hookResult . ' '
              . $eid . ' '
              . $mid . ' ' . '"'
              . $alarm->{MonitorName} . '" ' . '"'
              . $resTxt . '" ' . '"'
              . $resJsonString . '" ';

            if ($hooks_config{hook_pass_image_path}) {
              my $event = new ZoneMinder::Event($eid);
              $user_cmd = $user_cmd . ' "' . $event->Path() . '"';
              main::Debug(1, 'Adding event path:'
                  . $event->Path()
                  . ' to $user_cmd for image location');
            }

            if ( $user_cmd =~ /^(.*)$/ ) {
              $user_cmd = $1;
            }
            main::Debug(1, "invoking user start notification script $user_cmd");
            my $user_res = `$user_cmd`;
          } # user notify script

          if ( $hooks_config{use_hook_description} && $hookResult == 0 ) {
            $alarm->{Start}->{Cause} = $resTxt . ' ' . $alarm->{Start}->{Cause};
            $alarm->{Start}->{DetectionJson} = decode_json($resJsonString);

            print main::WRITER 'active_event_update--TYPE--'
              . $mid
              . '--SPLIT--'
              . $eid
              . '--SPLIT--' . 'Start'
              . '--SPLIT--' . 'Cause'
              . '--SPLIT--'
              . $alarm->{Start}->{Cause}
              . '--JSON--'
              . $resJsonString . "\n";

            print main::WRITER 'event_description--TYPE--'
              . $mid
              . '--SPLIT--'
              . $eid
              . '--SPLIT--'
              . $resTxt . "\n";

            $hookString = $resTxt;
          }

          if ($hooks_config{tag_detected_objects} && $hookResult == 0 && $resJsonString) {
            eval {
              my $det = decode_json($resJsonString);
              my @labels;
              for my $item (@$det) {
                push @labels, $item->{label} if $item->{label};
              }
              tagEventObjects($eid, \@labels) if @labels;
            };
            main::Error("tagEventObjects (event_start): $@") if $@;
          }
        } else {
          main::Info(
            'use hooks/start hook not being used, going to directly send out a notification if checks pass'
          );
          $hookResult = 0;
        }

        $alarm->{Start}->{State} = 'ready';
      }
    } elsif ( $alarm->{Start}->{State} eq 'ready' ) {

      my ( $rulesAllowed, $rulesObject ) = isAllowedInRules($alarm);
      if ( !$rulesAllowed ) {
        main::Debug(1, 'rules: Not processing start notifications as rules checks failed');
      } else {
        my $cause          = $alarm->{Start}->{Cause};
        my $detectJson     = $alarm->{Start}->{DetectionJson} || [];
        my $temp_alarm_obj = {
          Name          => $mname,
          MonitorId     => $mid,
          EventId       => $eid,
          Cause         => $cause,
          DetectionJson => $detectJson,
          RulesObject   => $rulesObject
        };

        if ( $push_config{enabled} && $push_config{script} ) {
          if ( isAllowedChannel( 'event_start', 'api', $hookResult )
            || !$hooks_config{event_start_hook}
            || !$hooks_config{enabled} )
          {
            main::Info('Sending push over API as it is allowed for event_start');

            my $api_cmd =
              $push_config{script} . ' '
              . $eid . ' '
              . $mid . ' ' . ' "'
              . $temp_alarm_obj->{Name} . '" ' . ' "'
              . $temp_alarm_obj->{Cause} . '" '
              . ' event_start';

            if ($hooks_config{hook_pass_image_path}) {
              my $event = new ZoneMinder::Event($eid);
              $api_cmd = $api_cmd . ' "' . $event->Path() . '"';
              main::Debug(2, 'Adding event path:'
                  . $event->Path()
                  . ' to api_cmd for image location');
            }

            main::Info("Executing API script command for event_start $api_cmd");
            if ( $api_cmd =~ /^(.*)$/ ) {
              $api_cmd = $1;
            }
            my $api_res = `$api_cmd`;
            main::Info("Returned from $api_cmd");
            chomp($api_res);
            my $api_retcode = $? >> 8;
            main::Debug(1, "API push script returned : $api_retcode");
          } else {
            main::Info(
              'Not sending push over API as it is not allowed for event_start');
          }
        }
        main::Debug(1, 'Matching alarm to connection rules...');
        my ($serv) = @_;
        my %fcm_token_duplicates = ();
        foreach (@main::active_connections) {
          if ($_->{token} && $fcm_token_duplicates{$_->{token}}) {
            main::Debug(1, '...'.substr($_->{token},-10).' occurs mutiples times. NOT USUAL, ignoring');
            next;
          }
          if ( shouldSendEventToConn( $temp_alarm_obj, $_ ) ) {
            main::Debug(1, 'token is unique, shouldSendEventToConn returned true, so calling sendEvent');
            sendEvent( $temp_alarm_obj, $_, 'event_start', $hookResult );
            $fcm_token_duplicates{$_->{token}}++ if $_->{token};
          }
        }
      }
      $alarm->{Start}->{State} = 'done';
    }
    elsif ( ($alarm->{End}->{State} // '') eq 'pending' ) {
      if ( { map { $_ => 1 } split(',', $hooks_config{hook_skip_monitors} // '') }->{$mid} ) {
        main::Info("$mid is in hook skip list, not using hooks");
        $alarm->{End}->{State} = 'ready';
        $hookResult = 0;
      }
      else {
      if ( $alarm->{Start}->{State} ne 'done' ) {
        main::Debug(2, 'Not yet sending out end notification as start hook/notify is not done');

      } else {
        my $notes = getNotesFromEventDB($eid);
        if ($hookString) {
          if ( index( $notes, 'detected:' ) == -1 ) {
            main::Debug(1, "ZM overwrote detection DB, current notes: [$notes], adding detection notes back into DB [$hookString]");

            # This will be prefixed, so no need to add old notes back
            updateEventinZmDB( $eid, $hookString );
            $notes = $hookString . " " . $notes;
          } else {
            main::Debug(2, "DB Event notes contain detection text, all good");
          }
        }

        if ( $hooks_config{event_end_hook} && $hooks_config{enabled} ) {

          my $cmd =
              $hooks_config{event_end_hook} . ' '
            . $eid . ' '
            . $mid . ' "'
            . $alarm->{MonitorName} . '" "'
            . $notes . '"';

          if ($hooks_config{hook_pass_image_path}) {
            my $event = new ZoneMinder::Event($eid);
            $cmd = $cmd . ' "' . $event->Path() . '"';
            main::Debug(2, 'Adding event path:'
                . $event->Path()
                . ' to hook for image storage');
          }
          main::Debug(1, 'Invoking hook on event end:' . $cmd);
          if ( $cmd =~ /^(.*)$/ ) {
            $cmd = $1;
          }

          print main::WRITER "update_parallel_hooks--TYPE--add\n";
          my $res = `$cmd`;
          $hookResult = $? >> 8;

          print main::WRITER "update_parallel_hooks--TYPE--del\n";

          chomp($res);
          my ( $resTxt, $resJsonString ) = parseDetectResults($res);
          $hookResult = 1 if (!$resTxt);

          $alarm->{End}->{State} = 'ready';
          main::Debug(1, "hook end returned with text:$resTxt  json:$resJsonString exit:$hookResult");

          $alarm->{End}->{Cause}         = $resTxt;
          $alarm->{End}->{DetectionJson} = decode_json($resJsonString);

          if ($hooks_config{event_end_hook_notify_userscript}) {
            my $user_cmd =
                $hooks_config{event_end_hook_notify_userscript} . ' '
              . $hookResult . ' '
              . $eid . ' '
              . $mid . ' ' . '"'
              . $alarm->{MonitorName} . '" ' . '"'
              . $resTxt . '" ' . '"'
              . $resJsonString . '" ';

            if ($hooks_config{hook_pass_image_path}) {
              my $event = new ZoneMinder::Event($eid);
              $user_cmd = $user_cmd . ' "' . $event->Path() . '"';
              main::Debug(2, 'Adding event path:'
                  . $event->Path()
                  . ' to $user_cmd for image location');

            }

            if ( $user_cmd =~ /^(.*)$/ ) {
              $user_cmd = $1;
            }
            main::Debug(1, "invoking user end notification script $user_cmd");
            my $user_res = `$user_cmd`;
          } # user notify script

          if ($hooks_config{use_hook_description} &&
              ($hookResult == 0) && (index($resTxt,'detected:') != -1)) {
            main::Debug(1, "Event end: overwriting notes with $resTxt");
            $alarm->{End}->{Cause} = $resTxt . ' ' . $alarm->{End}->{Cause};
            $alarm->{End}->{DetectionJson} = decode_json($resJsonString);

            print main::WRITER 'active_event_update--TYPE--'
              . $mid
              . '--SPLIT--'
              . $eid
              . '--SPLIT--' . 'End'
              . '--SPLIT--' . 'Cause'
              . '--SPLIT--'
              . $alarm->{End}->{Cause}
              . '--JSON--'
              . $resJsonString . "\n";

            print main::WRITER 'event_description--TYPE--'
              . $mid
              . '--SPLIT--'
              . $eid
              . '--SPLIT--'
              . $resTxt . "\n";

            $hookString = $resTxt;
          }

          if ($hooks_config{tag_detected_objects} && $hookResult == 0 && $resJsonString) {
            eval {
              my $det = decode_json($resJsonString);
              my @labels;
              for my $item (@$det) {
                push @labels, $item->{label} if $item->{label};
              }
              tagEventObjects($eid, \@labels) if @labels;
            };
            main::Error("tagEventObjects (event_end): $@") if $@;
          }
        } else {
          main::Info(
            'end hooks/use hooks not being used, going to directly send out a notification if checks pass'
          );
          $hookResult = 0;
        }

        $alarm->{End}->{State} = 'ready';
      }
      }
    }
    elsif ( ($alarm->{End}->{State} // '') eq 'ready' ) {

      my ( $rulesAllowed, $rulesObject ) = isAllowedInRules($alarm);

      if ( $hooks_config{event_end_notify_if_start_success} && ($startHookResult != 0) ) {
        main::Info(
          'Not sending event end alarm, as we did not send a start alarm for this, or start hook processing failed'
        );
      } elsif ( !$rulesAllowed ) {
        main::Debug(1, 'rules: Not processing end notifications as rules checks failed for start notification');
      } else {
        my $cause          = $alarm->{End}->{Cause};
        my $detectJson     = $alarm->{End}->{DetectionJson} || [];
        my $temp_alarm_obj = {
          Name          => $mname,
          MonitorId     => $mid,
          EventId       => $eid,
          Cause         => $cause,
          DetectionJson => $detectJson,
          RulesObject   => $rulesObject
        };

        if ( $push_config{enabled} && $push_config{script} ) {
          if ($notify_config{send_event_end_notification}) {
            if ( isAllowedChannel( 'event_end', 'api', $hookResult )
              || !$hooks_config{event_end_hook}
              || !$hooks_config{enabled} )
            {
              main::Debug(1, 'Sending push over API as it is allowed for event_end');

              my $api_cmd =
                  $push_config{script} . ' '
                . $eid . ' '
                . $mid . ' ' . ' "'
                . $temp_alarm_obj->{Name} . '" ' . ' "'
                . $temp_alarm_obj->{Cause} . '" '
                . ' event_end';

              if ($hooks_config{hook_pass_image_path}) {
                my $event = new ZoneMinder::Event($eid);
                $api_cmd = $api_cmd . ' "' . $event->Path() . '"';
                main::Debug(2, 'Adding event path:'
                    . $event->Path()
                    . ' to api_cmd for image location');
              }
              main::Info("Executing API script command for event_end $api_cmd");

              if ( $api_cmd =~ /^(.*)$/ ) {
                $api_cmd = $1;
              }
              my $res = `$api_cmd`;
              main::Debug(2, "returned from api cmd for event_end");
              chomp($res);
              my $retcode = $? >> 8;
              main::Debug(1, "API push script returned (event_end) : $retcode");
            } else {
              main::Debug(1, 'Not sending push over API as it is not allowed for event_start');
            }
          } else {
            main::Debug(1, 'Not sending event_end push over API as send_event_end_notification is no');
          }
        }

        main::Debug(1, 'Matching alarm to connection rules...');

        my ($serv) = @_;
        foreach (@main::active_connections) {
          if ( isInList( $_->{monlist}, $temp_alarm_obj->{MonitorId} ) ) {
            sendEvent( $temp_alarm_obj, $_, 'event_end', $hookResult );
          } else {
            main::Debug(1, 'Skipping FCM notification as Monitor:'
                . $temp_alarm_obj->{Name} . '('
                . $temp_alarm_obj->{MonitorId}
                . ') is excluded from zmNinja monitor list');
          }
        }
      }

      $alarm->{End}->{State} = 'done';
    }
    elsif ( ($alarm->{End}->{State} // '') eq 'done' ) {
      $doneProcessing = 1;
    }

    if ( !main::zmMemVerify($monitor) ) {
      main::Error('SHM failed, re-validating it');
      if (!main::loadMonitor($monitor)) {
        main::loadMonitors();
      }
    } else {
      my $state   = main::zmGetMonitorState($monitor);
      my $shm_eid = main::zmGetLastEvent($monitor);

      if ( ( $state == main::STATE_IDLE() || $state == main::STATE_TAPE() || $shm_eid != $eid )
        && !$endProcessed ) {
        main::Debug(2, "For $mid ($mname), SHM says: state=$state, eid=$shm_eid");
        main::Info("Event $eid for Monitor $mid has finished");
        $endProcessed = 1;

        $alarm->{End} = {
          State => 'pending',
          Time  => time(),
          Cause => getNotesFromEventDB($eid)
        };

        main::Debug(2, 'Event end object is: state=>'
            . $alarm->{End}->{State}
            . ' with cause=>'
            . $alarm->{End}->{Cause});
      }
    }
    sleep(2);
  } # end while loop

  main::Debug(1, 'exiting');
  print main::WRITER 'active_event_delete--TYPE--' . $mid . '--SPLIT--' . $eid . "\n";
  close(main::WRITER);
}

1;
