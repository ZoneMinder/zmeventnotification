#!/usr/bin/perl -T
#
# ==========================================================================
#
# THIS SCRIPT MUST BE RUN WITH SUDO OR STARTED VIA ZMDC.PL
#
# ZoneMinder Realtime Notification System
#
# A very light weight event notification daemon
# Uses shared memory to detect new events (polls SHM)
# Also opens a websocket connection at a configurable port
# so events can be reported
# Any client can connect to this web socket and handle it further
# for example, send it out via APNS/GCM or any other mechanism
#
# This is a much  faster and low overhead method compared to zmfilter
# as there is no DB overhead nor SQL searches for event matches

# ~ PP
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
# ==========================================================================


#perl -MCPAN -e "install Crypt::MySQL"
#perl -MCPAN -e "install Net::WebSocket::Server"

use Data::Dumper;

use strict;
use bytes;
# ==========================================================================
#
# These are the elements you can edit to suit your installation
#
# ==========================================================================
my $useAPNS = 1;				# set this to 1 if you have an APNS SSL certificate/key pair
						# the only way to have this is if you have an apple developer
						# account
my $isSandbox = 1;

use constant SSL_CERT_FILE=>'/etc/apache2/ssl/zoneminder.crt';	 # Change these to your certs/keys
use constant SSL_KEY_FILE=>'/etc/apache2/ssl/zoneminder.key';

use constant APNS_CERT_FILE=>'/etc/private/apns-dev-cert.pem';
use constant APNS_KEY_FILE=>'/etc/private/apns-dev-key.pem';
use constant APNS_TOKEN_FILE=>'/etc/private/tokens.txt';

use constant EVENT_NOTIFICATION_PORT=>9000; 			# port for Websockets connection


use constant SLEEP_DELAY=>5; 			# duration in seconds after which we will check for new events
use constant MONITOR_RELOAD_INTERVAL => 300;
use constant WEBSOCKET_AUTH_DELAY => 20; 		# max seconds by which authentication must be done
use constant APNS_FEEDBACK_CHECK_INTERVAL => 5;


use constant PENDING_WEBSOCKET => '1';
use constant INVALID_WEBSOCKET => '-1';
use constant INVALID_APNS => '-2';
use constant VALID_WEBSOCKET => '0';

if (!try_use ("Net::WebSocket::Server")) {Fatal ("Net::WebSocket::Server missing");exit (-1);}
if (!try_use ("IO::Socket::SSL")) {Fatal ("IO::Socket::SSL  missing");exit (-1);}
if (!try_use ("Crypt::MySQL qw(password password41)")) {Fatal ("Crypt::MySQL  missing");exit (-1);}
if (!try_use ("JSON")) 
{ 
	if (!try_use ("JSON::XS")) 
	{ Fatal ("JSON or JSON::XS  missing");exit (-1);}
} 

# These modules are needed only if APNS is enabled
if ($useAPNS)
{
	if (!try_use ("Net::APNS::Persistent") || !try_use ("Net::APNS::Feedback"))
	{
		Warning ("Net::APNS::Feedback and/or Net::APNS::Persistent not present. Disabling APNS support");
		$useAPNS = 0;

	}
	else
	{
		Info ("APNS support loaded");
	}
}
else
{
		Info ("APNS support disabled");
}

# ==========================================================================
#
# Don't change anything below here
#
# ==========================================================================

use lib '/usr/local/lib/x86_64-linux-gnu/perl5';
use ZoneMinder;
use POSIX;
use DBI;

$| = 1;

$ENV{PATH}  = '/bin:/usr/bin';
$ENV{SHELL} = '/bin/sh' if exists $ENV{SHELL};
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

sub Usage
{
    	print( "This daemon is not meant to be invoked from command line\n");
	exit( -1 );
}

# Try to load a perl module
# and if it is not available 
# generate a log 

sub try_use 
{
  my $module = shift;
  eval("use $module");
  return($@ ? 0:1);
}

logInit();
logSetSignal();

Info( "Event Notification daemon  starting\n" );

my $dbh = zmDbConnect();
my %monitors;
my $monitor_reload_time = 0;
my $apns_feedback_time = 0;
my $wss;
my @events=();
my @active_connections=();
my $alarm_header="";

loadTokens();
initSocketServer();
Info( "Event Notification daemon exiting\n" );
exit();

# This function uses shared memory polling to check if 
# ZM reported any new events. If it does find events
# then the details are packaged into the events array
# so they can be JSONified and sent out
sub checkEvents()
{
	
        my $len = scalar @active_connections;
 	Info ("Total connections: ".$len."\n");
	foreach (@active_connections)
	{
		#print " IP:".$_->{conn}->ip().":".$_->{conn}->port()."Token:".$_->{token}."\n";
	}

	my $eventFound = 0;
	if ( (time() - $monitor_reload_time) > MONITOR_RELOAD_INTERVAL )
    	{
		Info ("Reloading Monitors...\n");
		foreach my $monitor (values(%monitors))
		{
			zmMemInvalidate( $monitor );
		}
		loadMonitors();
	}


	@events = ();
	$alarm_header = "";
	foreach my $monitor ( values(%monitors) )
	{ 
		my ( $state, $last_event )
		    = zmMemRead( $monitor,
				 [ "shared_data:state",
				   "shared_data:last_event"
				 ]
		);
		if ($state == STATE_ALARM || $state == STATE_ALERT)
		{
			if ( !defined($monitor->{LastEvent})
                 	     || ($last_event != $monitor->{LastEvent}))
			{
				Info( "New event $last_event reported for ".$monitor->{Name}."\n");
				$monitor->{LastState} = $state;
				$monitor->{LastEvent} = $last_event;
				my $name = $monitor->{Name};
				my $mid = $monitor->{Id};
				my $eid = $last_event;
				push @events, {Name => $name, MonitorId => $mid, EventId => $last_event};
				$alarm_header = "Alarms: " if (!$alarm_header);
				$alarm_header = $alarm_header . $name .",";
				$eventFound = 1;
			}
			
		}
	}
	chop($alarm_header) if ($alarm_header);
	return ($eventFound);
}

# Refreshes list of monitors from DB
# 
sub loadMonitors
{
    Info( "Loading monitors\n" );
    $monitor_reload_time = time();

    my %new_monitors = ();

    my $sql = "SELECT * FROM Monitors
               WHERE find_in_set( Function, 'Modect,Mocord,Nodect' )"
    ;
    my $sth = $dbh->prepare_cached( $sql )
        or Fatal( "Can't prepare '$sql': ".$dbh->errstr() );
    my $res = $sth->execute()
        or Fatal( "Can't execute: ".$sth->errstr() );
    while( my $monitor = $sth->fetchrow_hashref() )
    {
        next if ( !zmMemVerify( $monitor ) ); # Check shared memory ok

        if ( defined($monitors{$monitor->{Id}}->{LastState}) )
        {
            $monitor->{LastState} = $monitors{$monitor->{Id}}->{LastState};
        }
        else
        {
            $monitor->{LastState} = zmGetMonitorState( $monitor );
        }
        if ( defined($monitors{$monitor->{Id}}->{LastEvent}) )
        {
            $monitor->{LastEvent} = $monitors{$monitor->{Id}}->{LastEvent};
        }
        else
        {
            $monitor->{LastEvent} = zmGetLastEvent( $monitor );
        }
        $new_monitors{$monitor->{Id}} = $monitor;
    }
    %monitors = %new_monitors;
}

# This function compares the password provided over websockets
# to the password stored in the ZM MYSQL DB

sub validateZM
{
	my ($u,$p) = @_;
	return 0 if ( $u eq "" || $p eq "");
	my $sql = 'select Password from Users where Username=?';
	my $sth = $dbh->prepare_cached($sql)
	 or Fatal( "Can't prepare '$sql': ".$dbh->errstr() );
        my $res = $sth->execute( $u )
	or Fatal( "Can't execute: ".$sth->errstr() );
	if (my ($state) = $sth->fetchrow_hashref())
	{
		my $encryptedPassword = password41($p);
		$sth->finish();
		return $state->{Password} eq $encryptedPassword ? 1:0; 
	}
	else
	{
		$sth->finish();
		return 0;
	}

}


# This function is called when an alarm
# needs to be transmitted over APNS
sub sendOverAPNS
{
  if (!$useAPNS)
  {
	Info ("Rejecting APNS request as daemon has APNS disabled");
	return;
  }

  my ($obj, $header, $str) = @_;
  my (%hash) = %{$str}; 
      
    my $apns = Net::APNS::Persistent->new({
    sandbox => $isSandbox,
    cert    => APNS_CERT_FILE,
    key     => APNS_KEY_FILE
  });

   $obj->{badge}++;
   $apns->queue_notification(
	    $obj->{token},
	    {
	      aps => {
		  alert => $header,
		  sound => 'default',
		  badge => $obj->{badge},
	      },
	      alarm_details => \%hash
	    });

  $apns->send_queue;
  $apns->disconnect;

}



# This function polls APNS Feedback
# to see if any entries need to be removed
sub apnsFeedbackCheck
{

	if ((time() - $apns_feedback_time) > APNS_FEEDBACK_CHECK_INTERVAL)
	{
		if (!$useAPNS)
		{
			Info ("Rejecting APNS Feedback request as daemon has APNS disabled");
			return;
		}

		Info ("Checking APNS Feedback\n");
		$apns_feedback_time = time();
		my $apnsfb = Net::APNS::Feedback->new({
		sandbox => $isSandbox,
		cert    => APNS_CERT_FILE,
		key     => APNS_KEY_FILE
	  	});
	  	my @feedback = $apnsfb->retrieve_feedback;


		foreach (@feedback[0]->[0])
		{
			my $delete_token = $_->{token};
			if ($delete_token != "")
			{
				deleteToken($delete_token);
				foreach(@active_connections)
				{
					if ($_->{token} eq $delete_token)
					{
						$_->{pending} = INVALID_APNS;
						Info ("Marking entry as invalid apns token: ". $delete_token."\n");
					}
				}
			}
		}
	}
}

# This runs at each tick to purge connections
# that are inactive or have had an error
# This also closes any connection that has not provided
# credentials in the time configured after opening a socket

sub checkConnection
{
	foreach (@active_connections)
	{
		my $curtime = time();
		if ($_->{pending} == PENDING_WEBSOCKET)
		{
			if ($curtime - $_->{time} > WEBSOCKET_AUTH_DELAY)
			{
			# What happens if auth is not provided but device token is registered?
			# It may still be a bogus token, so don't risk keeping connection stored
				if (exists $_->{conn})
				{
					my $conn = $_->{conn};
					Info ("Rejecting ".$conn->ip()." - authentication timeout");
					$_->{pending} = INVALID_WEBSOCKET;
					my $str = encode_json({status=>'Fail', reason => 'NOAUTH'});
					eval {$_->{conn}->send_utf8($str);};
					$_->{conn}->disconnect();
				}
			}
		}

	}
	@active_connections = grep { $_->{pending} != INVALID_WEBSOCKET } @active_connections;
	if ($useAPNS)
	{
		@active_connections = grep { $_->{pending} != INVALID_APNS } @active_connections;
	}
}

# This function  is called whenever we receive a message from a client

sub checkMessage
{
	my ($conn, $msg) = @_;	
	my $json_string = decode_json($msg);

	# This event type is when a command related to push notification is received
	if (($json_string->{'event'} eq "push") && !$useAPNS)
	{
		my $str = encode_json({status=>'Fail', reason => 'APNSDISABLED'});
		eval {$conn->send_utf8($str);};
		return;
	}
	if (($json_string->{'event'} eq "push") && $useAPNS)
	{
		if ($json_string->{'data'}->{'type'} eq "badge")
		{
			foreach (@active_connections)
			{
				if ((exists $_->{conn}) && ($_->{conn}->ip() eq $conn->ip())  &&
				    ($_->{conn}->port() eq $conn->port()))  
				{

					#print "Badge match, setting to 0\n";
					$_->{badge} = $json_string->{'data'}->{'badge'};
				}
			}
		}
		# This sub type is when a device token is registered
		if ($json_string->{'data'}->{'type'} eq "token")
		{
			
			my $repeatToken=0;
			foreach (@active_connections)
			{
				if ($_->{token} eq $json_string->{'data'}->{'token'}) 
				{
					if ( (!exists $_->{conn}) || ($_->{conn}->ip() ne $conn->ip() && $_->{conn}->port() ne $conn->port()))
					{
						$_->{pending} = INVALID_APNS;
						Info ("Duplicate token found, marking for deletion");

					}
				}
				elsif ( (exists $_->{conn}) && ($_->{conn}->ip() eq $conn->ip())  &&
				    ($_->{conn}->port() eq $conn->port()))  
				{
					$_->{token} = $json_string->{'data'}->{'token'};
					Info ("Device token ".$_->{token}." stored for APNS");
					saveTokens($_->{token});
					$repeatToken=1; # if 1, remove any other occurrences


				}
			}

			# Now make sure there are no token duplicates
			my ($ac) = scalar @active_connections;
			my %filter;
			#print "OLD LEN: $ac\n";
				
			$ac = scalar @active_connections;	
			#print "NEW LEN: $ac\n";
		}
		# this sub type is when a push enable/disable or other control commands are sent
		if ($json_string->{'type'} eq "control")
		{
			foreach (@active_connections)
			{
				if ((exists $_->{conn}) && ($_->{conn}->ip() eq $conn->ip())  &&
				    ($_->{conn}->port() eq $conn->port()))  
				{

				# No control protocols defined for now
				}
			}		
		}
	}

	# This event type is when a command related to authorization is sent
	if ($json_string->{'event'} eq "auth")
	{
		my $uname = $json_string->{'data'}->{'user'};
		my $pwd = $json_string->{'data'}->{'password'};
	
		return if ($uname eq "" || $pwd eq "");
		foreach (@active_connections)
		{
			if ( (exists $_->{conn}) &&
			    ($_->{conn}->ip() eq $conn->ip())  &&
			    ($_->{conn}->port() eq $conn->port())  &&
			    ($_->{pending}==PENDING_WEBSOCKET))
			{
				if (!validateZM($uname,$pwd))
				{
					# bad username or password, so reject and mark for deletion
					my $str = encode_json({status=>'Fail', reason => 'BADAUTH'});
					eval {$_->{conn}->send_utf8($str);};
					Info("Bad authentication provided by ".$_->{conn}->ip());
					$_->{pending}=INVALID_WEBSOCKET;
				}
				else
				{


					# all good, connection auth was valid
					$_->{pending}=VALID_WEBSOCKET;
					$_->{token}='';
					my $str = encode_json({status=>'Success', reason => ''});
					eval {$_->{conn}->send_utf8($str);};
					Info("Correct authentication provided by ".$_->{conn}->ip());
					
				}
			}
		}
	}
}

sub loadTokens
{
	return if (!$useAPNS);
	return if ( ! -f APNS_TOKEN_FILE);
	
	open (my $fh, '<', APNS_TOKEN_FILE);
	chomp( my @lines = <$fh>);
	close ($fh);
	my @uniquetokens = uniq(@lines);

	open ($fh, '>', APNS_TOKEN_FILE);

	foreach(@uniquetokens)
	{
		my $row = $_;
		next if ($row eq "");
		print $fh "$row\n";
		#print "load: PUSHING $row\n";
		push @active_connections, {
					   token => $row,
					   pending => VALID_WEBSOCKET,
					   time=>time(),
					   badge => 0
					  };
		
	}
	close ($fh);
}

sub deleteToken
{
	my $token = shift;
	return if (!$useAPNS);
	return if ( ! -f APNS_TOKEN_FILE);
	
	open (my $fh, '<', APNS_TOKEN_FILE);
	chomp( my @lines = <$fh>);
	close ($fh);
	my @uniquetokens = uniq(@lines);

	open ($fh, '>', APNS_TOKEN_FILE);

	foreach(@uniquetokens)
	{
		my $row = $_;
		next if ($row eq "" || $row eq $token);
		print $fh "$row\n";
		#print "delete: $row\n";
		push @active_connections, {
					   token => $row,
					   pending => VALID_WEBSOCKET,
					   time=>time(),
					   badge => 0
					  };
		
	}
	close ($fh);
}

sub saveTokens
{
	my $token = shift;
	open (my $fh, '>>', APNS_TOKEN_FILE);
	print $fh "$token\n";
	close ($fh);
	#print "Saved Token $token to file\n";
	
}

sub uniq {
    my %seen;
    grep !$seen{$_}++, @_;
}


# This is really the main module
# It opens a WSS socket and keeps listening
sub initSocketServer
{
	checkEvents();

	my $ssl_server = IO::Socket::SSL->new(
      	      Listen        => 10,
	      LocalPort     => EVENT_NOTIFICATION_PORT,
	      Proto         => 'tcp',
	      Reuse	    => 1,
	      SSL_cert_file => SSL_CERT_FILE,
	      SSL_key_file  => SSL_KEY_FILE
	    ) or die "failed to listen: $!";

	Info ("Web Socket Event Server listening on port ".EVENT_NOTIFICATION_PORT."\n");

	$wss = Net::WebSocket::Server->new(
		listen => $ssl_server,
		tick_period => SLEEP_DELAY,
		on_tick => sub {
			checkConnection();
			apnsFeedbackCheck();
			my $ac = scalar @active_connections;
			if (checkEvents())
			{
				Info ("Broadcasting new events to all $ac websocket clients\n");
					my ($serv) = @_;
					my $str = encode_json({status=>'Success', events => \@events});
					my %hash_str = (status=>'Success', events => \@events);
					my $i = 0;
					foreach (@active_connections)
					{
						$i++;
						# if there is APNS send it over APNS
						if ($_->{token} ne "")
						{
							sendOverAPNS($_,$alarm_header, \%hash_str) ;
						}
						# if there is a websocket send it over websockets
						elsif ($_->{pending} == VALID_WEBSOCKET)
						{
							if (exists $_->{conn})
							{
								Info ($_->{conn}->ip()."-sending over websockets\n");
								eval {$_->{conn}->send_utf8($str);};
								if ($@)
								{
							
									$_->{pending} = INVALID_WEBSOCKET;
								}
							}
						}
						

						
					}


			}
		},
		on_connect => sub {
			my ($serv, $conn) = @_;
			my ($len) = scalar @active_connections;
			Info ("got a websocket connection from ".$conn->ip()." (". $len.") active connections");
			$conn->on(
				utf8 => sub {
					my ($conn, $msg) = @_;
					checkMessage($conn, $msg);
				},
				handshake => sub {
					my ($conn, $handshake) = @_;
					Info ("Websockets: New Connection Handshake requested from ".$conn->ip().":".$conn->port()." state=pending auth");
					my $connect_time = time();
					push @active_connections, {conn => $conn, 
								   pending => PENDING_WEBSOCKET, 
								   time=>$connect_time, 
								   badge => 0};
				},
				disconnect => sub
				{
					my ($conn, $code, $reason) = @_;
					Info ("Websocket remotely disconnected from ".$conn->ip());
					foreach (@active_connections)
					{
						if ((exists $_->{conn}) && ($_->{conn}->ip() eq $conn->ip())  &&
                    				    ($_->{conn}->port() eq $conn->port()))
						{
							# mark this for deletion only if device token
							# not present
							if ( $_->{token} eq '')
							{
								$_->{pending}=INVALID_WEBSOCKET; 
								Info( "Marking ".$conn->ip()." for deletion as websocket closed remotely\n");
							}
							else
							{
								
								Info( "NOT Marking ".$conn->ip()." for deletion as token ".$_->{token}." active\n");
							}
						}

					}
				},
			);

			
		}
	)->start;
}
