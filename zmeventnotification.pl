#!/usr/bin/perl  -T
#
# ==========================================================================
#
# THIS SCRIPT MUST BE RUN WITH SUDO OR STARTED VIA ZMDC.PL
#
# ZoneMinder Realtime Notification System
#
# A  light weight event notification daemon
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



#sudo perl -MCPAN -e "install Crypt::MySQL"
#sudo perl -MCPAN -e "install Net::WebSocket::Server"

#For pushProxy
#sudo perl -MCPAN -e "install LWP::Protocol::https"

#For iOS APNS:
#sudo perl -MCPAN -e "install Net::APNS::Persistent"


use File::Basename;
use Data::Dumper;

use strict;
use bytes;

my $app_version="0.5";

# ==========================================================================
#
# These are the elements you can edit to suit your installation
#
# ==========================================================================
use constant EVENT_NOTIFICATION_PORT=>9000; 				# port for Websockets connection
use constant SSL_CERT_FILE=>'/etc/apache2/ssl/zoneminder.crt';		# Change these to your certs/keys
use constant SSL_KEY_FILE=>'/etc/apache2/ssl/zoneminder.key';


# if you only want to enable websockets make both of these 0

my $usePushProxy = 1;				# set this to 1 to use a remote push proxy for APNS that I have set up for zmNinja users

my $usePushAPNSDirect = 0;			# set this to 1 if you have an APNS SSL certificate/key pair
						# the only way to have this is if you have an apple developer
						# account

my $pushProxyURL = 'https://pliablepixels.ddns.net:8801';  # This is my proxy URL. Don't change it unless you are hosting your on APNS AS

# PUSH_TOKEN_FILE is needed for pushProxy mode as well as direct APNS mode
# change this to a directory and file of your choosing. 
# This server will create the file if it does not exist

use constant PUSH_TOKEN_FILE=>'/etc/private/tokens.txt'; # MAKE SURE THIS DIRECTORY HAS WWW-DATA PERMISSIONS


# -------- There seems to be an LWP perl bug that fails certifying self signed certs
# refer to https://bugs.launchpad.net/ubuntu/+source/libwww-perl/+bug/1408331
# you don't have to make it this drastic, you can also follow other tips in that thread to point to
# a mozilla cert. I haven't tried

my %ssl_push_opts = ( ssl_opts=>{verify_hostname => 0,SSL_verify_mode => 0,SSL_verifycn_scheme => 'none'} );


#----------- Start: Change these only if you have usePushAPNSDirect set to 1 ------------------

my $isSandbox = 1;				# 1 or 0 depending on your APNS certificate

use constant APNS_CERT_FILE=>'/etc/private/apns-dev-cert.pem';  # only used if usePushAPNSDirect is enabled
use constant APNS_KEY_FILE=>'/etc/private/apns-dev-key.pem';	# only used if usePushAPNSDirect is enabled

use constant APNS_FEEDBACK_CHECK_INTERVAL => 3600;		# only used if usePushAPNSDirect is enabled

#----------- End: only applies to usePushAPNSDirect = 1 --

use constant PUSH_CHECK_REACH_INTERVAL => 3600;				# time in seconds to do a reachability test with push proxt
use constant SLEEP_DELAY=>5; 						# duration in seconds after which we will check for new events
use constant MONITOR_RELOAD_INTERVAL => 300;
use constant WEBSOCKET_AUTH_DELAY => 20; 				# max seconds by which authentication must be done

# These are needed for the remote push to work. Don't change these
use constant PUSHPROXY_APP_NAME => 'zmninjapro';
use constant PUSHPROXY_APP_ID => '3905d86d1f2922ed8f77583058471d70';


use constant PENDING_WEBSOCKET => '1';
use constant INVALID_WEBSOCKET => '-1';
use constant INVALID_APNS => '-2';
use constant VALID_WEBSOCKET => '0';

my $alarmEventId = 1;			# tags the event id along with the alarm - useful for correlation
					# only for geeks though - most people won't give a damn. I do.

if (!try_use ("Net::WebSocket::Server")) {Fatal ("Net::WebSocket::Server missing");exit (-1);}
if (!try_use ("IO::Socket::SSL")) {Fatal ("IO::Socket::SSL  missing");exit (-1);}
if (!try_use ("Crypt::MySQL qw(password password41)")) {Fatal ("Crypt::MySQL  missing");exit (-1);}

if (!try_use ("JSON")) 
{ 
	if (!try_use ("JSON::XS")) 
	{ Fatal ("JSON or JSON::XS  missing");exit (-1);}
} 

if ($usePushProxy)
{
	if ($usePushAPNSDirect)
	{
		$usePushAPNSDirect = 0; 
		Info ("Disabling direct push as push proxy is enabled");
	}
	if (!try_use ("LWP::UserAgent") || !try_use ("URI::URL") || !try_use("LWP::Protocol::https"))
	{
		Error ("Disabling PushProxy. PushProxy mode needs LWP::Protocol::https, LWP::UserAgent and URI::URL perl packages installed");
		$usePushProxy = 0;
	}
	else
	{
		Info ("Push enabled via PushProxy");
	}
	
}
else
{
	Info ("Push Proxy disabled");
}
# These modules are needed only if DirectPush is enabled and PushProxy is disabled
if ($usePushAPNSDirect )
{
	if (!try_use ("Net::APNS::Persistent") || !try_use ("Net::APNS::Feedback"))
	{
		Error ("Net::APNS::Feedback and/or Net::APNS::Persistent not present. Disabling direct APNS support");
		$usePushAPNSDirect = 0;

	}
	else
	{
		Info ("direct APNS support loaded");
	}
}
else
{
	Info ("direct APNS disabled");
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

logInit();
logSetSignal();


my $dbh = zmDbConnect();
my %monitors;
my $monitor_reload_time = 0;
my $apns_feedback_time = 0;
my $proxy_reach_time=0;
my $wss;
my @events=();
my @active_connections=();
my $alarm_header="";

# MAIN

if ($usePushAPNSDirect || $usePushProxy)
{
	my $dir = dirname(PUSH_TOKEN_FILE);
	if ( ! -d $dir)
	{

		Info ("Creating $dir to store APNS tokens");
		mkdir $dir;
	}
}

Info( "Event Notification daemon v $app_version starting\n" );
loadTokens();
initSocketServer();
Info( "Event Notification daemon exiting\n" );
exit();

# Try to load a perl module
# and if it is not available 
# generate a log 

sub try_use 
{
  my $module = shift;
  eval("use $module");
  return($@ ? 0:1);
}


# This function uses shared memory polling to check if 
# ZM reported any new events. If it does find events
# then the details are packaged into the events array
# so they can be JSONified and sent out
sub checkEvents()
{
	
	#foreach (@active_connections)
	#{
		#print " IP:".$_->{conn}->ip().":".$_->{conn}->port()."Token:".$_->{token}."\n";
	#}

	my $eventFound = 0;
	if ( (time() - $monitor_reload_time) > MONITOR_RELOAD_INTERVAL )
    	{
		my $len = scalar @active_connections;
		Info ("Total event client connections: ".$len."\n");

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
				$alarm_header = $alarm_header . $name ;
				$alarm_header = $alarm_header . " (".$last_event.") " if ($alarmEventId);
				$alarm_header = $alarm_header . "," ;
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

# Does a health check to make sure push proxy is reachable
sub testProxyURL
{
	if ((time() - $proxy_reach_time) > PUSH_CHECK_REACH_INTERVAL)
	{
		Info ("Checking $pushProxyURL reachability...");
		my $ua = LWP::UserAgent->new(%ssl_push_opts);
		$ua->timeout(10);
		$ua->env_proxy;
		my $response = $ua->get($pushProxyURL);
		if ($response->is_success)
		{
			Info ("PushProxy $pushProxyURL is reachable.");

		}
		else
		{
			Error ($response->status_line);
			Error ("PushProxy $pushProxyURL is NOT reachable. Notifications will not work. Please reach out to the proxy owner if this error persists");
		}
		$proxy_reach_time = time();

	}
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

# Passes on device token to the push proxy

sub registerOverPushProxy
{
	my ($token) = shift;
	my ($platform) = shift;
	my $uri = $pushProxyURL."/api/v2/tokens";
	my $json = '{"device":"'.$platform.'", "token":"'.$token.'", "channel":"default"}';
	my $req = HTTP::Request->new ('POST', $uri);
	$req->header( 'Content-Type' => 'application/json', 'X-AN-APP-NAME'=> PUSHPROXY_APP_NAME, 'X-AN-APP-KEY'=> PUSHPROXY_APP_ID
	 );
	 $req->content($json);
	my $lwp = LWP::UserAgent->new(%ssl_push_opts);
	my $res = $lwp->request( $req );
	if ($res->is_success)
	{
		Info ("Pushproxy registration success ".$res->content);
	}
	else
	{
		Warning("Push Proxy Token registration Error:".$res->status_line);
	}

}

# Sends a push notification to the remote proxy 
sub sendOverPushProxy
{
	
	my ($obj, $header, $str) = @_;
	$obj->{badge}++;
	my $uri = $pushProxyURL."/api/v2/push";
	my $json;

	# Not passing full JSON object - so that payload is limited for now
	if ($obj->{platform} eq "ios")
	{
		$json = '{"device":"'.$obj->{platform}.'", "token":"'.$obj->{token}.'", "alert":"'.$header.'", "sound":"blop.caf", "badge":"'.$obj->{badge}.'"}';
		#$json = '{"device":"'.$obj->{platform}.'", "token":"'.$obj->{token}.'", "alert":"'.$header.'",  "badge":"'.$obj->{badge}.'"}';
			}
	else
	{
		$json = '{"device":"'.$obj->{platform}.'", "token":"'.$obj->{token}.'", "sound":"blop", "alert":"'.$header.'"}';
		#$json = '{"device":"'.$obj->{platform}.'", "token":"'.$obj->{token}.'", "sound":"blop", "alert":"'.$header.'", "data":{"alarm_details":'.$str.'}}';
	}
	#print "Sending:$json\n";
	my $req = HTTP::Request->new ('POST', $uri);
	$req->header( 'Content-Type' => 'application/json', 'X-AN-APP-NAME'=> PUSHPROXY_APP_NAME, 'X-AN-APP-KEY'=> PUSHPROXY_APP_ID
	 );
	 $req->content($json);
	my $lwp = LWP::UserAgent->new(%ssl_push_opts);
	my $res = $lwp->request( $req );
	if ($res->is_success)
	{
		Info ("Pushproxy push message success ".$res->content);
	}
	else
	{
		Info("Push Proxy push message Error:".$res->status_line);
	}
}


# This function is called when an alarm
# needs to be transmitted over APNS
# called only if direct APNS mode is enabled
sub sendOverAPNS
{
  if (!$usePushAPNSDirect)
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
# only applicable for direct apns mode
sub apnsFeedbackCheck
{

	
	if ((time() - $apns_feedback_time) > APNS_FEEDBACK_CHECK_INTERVAL)
	{
		if ($usePushProxy)
		{
			Info ("Not checking APNS feedback in PushProxy Mode");
			return;
		}
		if (!$usePushAPNSDirect)
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
			# This takes care of purging connections that have not authenticated
			if ($curtime - $_->{time} > WEBSOCKET_AUTH_DELAY)
			{
			# What happens if auth is not provided but device token is registered?
			# It may still be a bogus token, so don't risk keeping connection stored
				if (exists $_->{conn})
				{
					my $conn = $_->{conn};
					Info ("Rejecting ".$conn->ip()." - authentication timeout");
					$_->{pending} = INVALID_WEBSOCKET;
					my $str = encode_json({event => 'auth', type=>'',status=>'Fail', reason => 'NOAUTH'});
					eval {$_->{conn}->send_utf8($str);};
					$_->{conn}->disconnect();
				}
			}
		}

	}
	@active_connections = grep { $_->{pending} != INVALID_WEBSOCKET } @active_connections;
	if ($usePushAPNSDirect || $usePushProxy)
	{
		@active_connections = grep { $_->{pending} != INVALID_APNS } @active_connections;
	}
}

# This function  is called whenever we receive a message from a client

sub checkMessage
{
	my ($conn, $msg) = @_;	
	
	my $json_string;
	eval {$json_string = decode_json($msg);};
	if ($@)
	{
		
		my $str = encode_json({event=> 'malformed', type=>'', status=>'Fail', reason=>'BADJSON'});
		eval {$conn->send_utf8($str);};
		return;
	}

	
	#print "Message:$msg\n";

	# This event type is when a command related to push notification is received
	if (($json_string->{'event'} eq "push") && !$usePushAPNSDirect && !$usePushProxy)
	{
		my $str = encode_json({event=>'push', type=>'',status=>'Fail', reason => 'PUSHDISABLED'});
		eval {$conn->send_utf8($str);};
		return;
	}
	#-----------------------------------------------------------------------------------
	# "push" event processing
	#-----------------------------------------------------------------------------------
	elsif (($json_string->{'event'} eq "push") && ($usePushAPNSDirect || $usePushProxy))
	{
		# sets the unread event count of events for a specific connection
		# the server keeps a tab of # of events it pushes out per connection
		# but won't know when the client has read them, so the client call tell the server
		# using this message
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
			
			# a token must have a platform otherwise I don't know whether to use APNS or GCM
			if (!$json_string->{'data'}->{'platform'})
			{
				my $str = encode_json({event=>'push', type=>'token',status=>'Fail', reason => 'MISSINGPLATFORM'});
				eval {$conn->send_utf8($str);};
				return;
			}
			foreach (@active_connections)
			{
				# this token already exists
				if ($_->{token} eq $json_string->{'data'}->{'token'}) 
				{
					# if the token doesn't belong to the same connection
					# then we have two connections owning the same token
					# so we need to delete the old one. This can happen when you load
					# the token from the persistent file and there is no connection
					# and then the client is loaded 
					if ( (!exists $_->{conn}) || ($_->{conn}->ip() ne $conn->ip() 
						&& $_->{conn}->port() ne $conn->port()))
					{
						$_->{pending} = INVALID_APNS;
						Info ("Duplicate token found, marking for deletion");

					}
					else # token matches and connection matches, so it may be an update
					{
						$_->{token} = $json_string->{'data'}->{'token'};
						$_->{platform} = $json_string->{'data'}->{'platform'};
						$_->{monlist} = "-1";
						$_->{intlist} = "-1";
						$_->{pushstate} = $json_string->{'data'}->{'state'};
						Info ("Storing token ...".substr($_->{token},-10).",monlist:".$_->{monlist}.",intlist:".$_->{intlist}.",pushstate:".$_->{pushstate}."\n");
						my ($emonlist,$eintlist) = saveTokens($_->{token}, $_->{monlist}, $_->{intlist}, $_->{platform}, $_->{pushstate});
						$_->{monlist} = $emonlist;
						$_->{intlist} = $eintlist;
					}
				}
				# The connection matches but the token does not 
				# this can happen if this is the first token registration after push notification registration
				# response is received
				elsif ( (exists $_->{conn}) && ($_->{conn}->ip() eq $conn->ip())  &&
				    ($_->{conn}->port() eq $conn->port()))  
				{
					$_->{token} = $json_string->{'data'}->{'token'};
					$_->{platform} = $json_string->{'data'}->{'platform'};
					$_->{monlist} = "-1";
					$_->{intlist} = "-1";
					$_->{pushstate} = $json_string->{'data'}->{'state'};
					Info ("Storing token ...".substr($_->{token},-10).",monlist:".$_->{monlist}.",intlist:".$_->{intlist}.",pushstate:".$_->{pushstate}."\n");
					my ($emonlist,$eintlist) = saveTokens($_->{token}, $_->{monlist}, $_->{intlist}, $_->{platform}, $_->{pushstate});
					$_->{monlist} = $emonlist;
					$_->{intlist} = $eintlist;


				}
			}

				
		}
		
	} # event = push
	#-----------------------------------------------------------------------------------
	# "control" event processing
	#-----------------------------------------------------------------------------------
	elsif (($json_string->{'event'} eq "control") )
	{
		if  ($json_string->{'data'}->{'type'} eq "filter")
		{
			if (!$json_string->{'data'}->{'monlist'})
			{
				my $str = encode_json({event=>'control', type=>'filter',status=>'Fail', reason => 'MISSINGMONITORLIST'});
				eval {$conn->send_utf8($str);};
				return;
			}
			if (!$json_string->{'data'}->{'intlist'})
			{
				my $str = encode_json({event=>'control', type=>'filter',status=>'Fail', reason => 'MISSINGINTERVALLIST'});
				eval {$conn->send_utf8($str);};
				return;
			}
			my $monlist = $json_string->{'data'}->{'monlist'};
			my $intlist = $json_string->{'data'}->{'intlist'};
			#print ("CONTROL GOT: $monlist and $intlist\n");
			foreach (@active_connections)
			{
				if ((exists $_->{conn}) && ($_->{conn}->ip() eq $conn->ip())  &&
				    ($_->{conn}->port() eq $conn->port()))  
				{

					$_->{monlist} = $monlist;
					$_->{intlist} = $intlist;
					Info ("Contrl: Storing token ...".substr($_->{token},-10).",monlist:".$_->{monlist}.",intlist:".$_->{intlist}.",pushstate:".$_->{pushstate}."\n");
					saveTokens($_->{token}, $_->{monlist}, $_->{intlist}, $_->{platform}, $_->{pushstate});	
				}
			}
		}	
		if  ($json_string->{'data'}->{'type'} eq "version")
		{
			foreach (@active_connections)
			{
				if ((exists $_->{conn}) && ($_->{conn}->ip() eq $conn->ip())  &&
				    ($_->{conn}->port() eq $conn->port()))  
				{
					my $str = encode_json({event=>'control',type=>'version', status=>'Success', reason => '', version => $app_version});
					eval {$_->{conn}->send_utf8($str);};

				}
			}
		}

	} # event = control


	#-----------------------------------------------------------------------------------
	# "auth" event processing
	#-----------------------------------------------------------------------------------
	# This event type is when a command related to authorization is sent
	elsif ($json_string->{'event'} eq "auth")
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
					my $str = encode_json({event=>'auth', type=>'', status=>'Fail', reason => 'BADAUTH'});
					eval {$_->{conn}->send_utf8($str);};
					Info("Bad authentication provided by ".$_->{conn}->ip());
					$_->{pending}=INVALID_WEBSOCKET;
				}
				else
				{


					# all good, connection auth was valid
					$_->{pending}=VALID_WEBSOCKET;
					$_->{token}='';
					my $str = encode_json({event=>'auth', type=>'', status=>'Success', reason => '', version => $app_version});
					eval {$_->{conn}->send_utf8($str);};
					Info("Correct authentication provided by ".$_->{conn}->ip());
					
				}
			}
		}
	} # event = auth
	else
	{
					my $str = encode_json({event=>$json_string->{'event'},type=>'', status=>'Fail', reason => 'NOTSUPPORTED'});
					eval {$_->{conn}->send_utf8($str);};
	}
}

# This loads APNS tokens stored in a conf file
# This ensures even if the daemon dies and 
# restarts APNS tokens are maintained
# I also maintain monitor filter list
# so that APNS notifications will only be pushed
# for the monitors that are configured against
# that token 

sub loadTokens
{
	return if (!$usePushAPNSDirect && !$usePushProxy);
	if ( ! -f PUSH_TOKEN_FILE)
	{
		open (my $foh, '>', PUSH_TOKEN_FILE);
		Info ("Creating ".PUSH_TOKEN_FILE);
		print $foh "";
		close ($foh);
	}
	
	open (my $fh, '<', PUSH_TOKEN_FILE);
	chomp( my @lines = <$fh>);

	close ($fh);
	my @uniquetokens = uniq(@lines);

	open ($fh, '>', PUSH_TOKEN_FILE);
	# This makes sure we rewrite the file with
	# unique tokens
	foreach(@uniquetokens)
	{
		next if ($_ eq "");
		print $fh "$_\n";
		my ($token, $monlist, $intlist, $platform, $pushstate)  = split (":",$_);
		#print "load: PUSHING $row\n";
		push @active_connections, {
			   token => $token,
			   pending => VALID_WEBSOCKET,
			   time=>time(),
			   badge => 0,
			   monlist => $monlist,
			   intlist => $intlist,
			   last_sent=>{},
			   platform => $platform,
			   pushstate => $pushstate
			  };
		
	}
	close ($fh);
}

# This is called if the APNS feedback channel
# reports an invalid token. We also remove it from
# our token file
sub deleteToken
{
	my $dtoken = shift;
	return if (!$usePushAPNSDirect && !$usePushProxy);
	return if ( ! -f PUSH_TOKEN_FILE);
	
	open (my $fh, '<', PUSH_TOKEN_FILE);
	chomp( my @lines = <$fh>);
	close ($fh);
	my @uniquetokens = uniq(@lines);

	open ($fh, '>', PUSH_TOKEN_FILE);

	foreach(@uniquetokens)
	{
		my ($token, $monlist, $intlist, $platform, $pushstate)  = split (":",$_);
		next if ($_ eq "" || $token eq $dtoken);
		print $fh "$_\n";
		#print "delete: $row\n";
		push @active_connections, {
					   token => $token,
					   pending => VALID_WEBSOCKET,
					   time=>time(),
					   badge => 0,
					   monlist => $monlist,
					   intlist => $intlist,
					   last_sent=>{},
					   platform => $platform,
					   pushstate => $pushstate
					  };
		
	}
	close ($fh);
}

# When a client sends a token id,
# I store it in the file
# It can be sent multiple times, with or without
# monitor list, so I retain the old monitor
# list if its not supplied. In the case of zmNinja
# tokens are sent without monitor list when the registration
# id is received from apple, so we handle that situation

sub saveTokens
{
	return if (!$usePushAPNSDirect && !$usePushProxy);
	my $stoken = shift;
	return if ($stoken eq "");
	my $smonlist = shift;
	my $sintlist = shift;
	my $splatform = shift;
	my $spushstate = shift;
	return if ($stoken eq "");
	open (my $fh, '<', PUSH_TOKEN_FILE) || Fatal ("Cannot open for read".PUSH_TOKEN_FILE);
	chomp( my @lines = <$fh>);
	close ($fh);
	my @uniquetokens = uniq(@lines);
	my $found = 0;
	open (my $fh, '>', PUSH_TOKEN_FILE) || Fatal ("Cannot open for write ".PUSH_TOKEN_FILE);
	foreach (@uniquetokens)
	{
		next if ($_ eq "");
		my ($token, $monlist, $intlist, $platform, $pushstate)  = split (":",$_);
		if ($token eq $stoken)
		{
			$smonlist = $monlist if ($smonlist eq "-1");
			$sintlist = $intlist if ($sintlist eq "-1");
			$spushstate = $pushstate if ($spushstate eq "");
			print $fh "$stoken:$smonlist:$sintlist:$splatform:$spushstate\n";
			$found = 1;
		}
		else
		{
			$pushstate="enabled" if ($pushstate="");
			print $fh "$token:$monlist:$intlist:$platform:$pushstate\n";
		}

	}

	$smonlist = "" if ($smonlist eq "-1");
	$sintlist = "" if ($sintlist eq "-1");
	
	print $fh "$stoken:$smonlist:$sintlist:$splatform:$spushstate\n" if (!$found);
	close ($fh);
	registerOverPushProxy($stoken,$splatform) if ($usePushProxy);
	#print "Saved Token $token to file\n";
	return ($smonlist, $sintlist);
	
}

# This keeps the latest of any duplicate tokens
# we need to ignore monitor list when we do this
sub uniq 
{
	my %seen;
   	my @array = reverse @_; # we want the latest
	my @farray=();
	foreach (@array)
	{
		my ($token,$monlist,$intlist,$platform, $pushstate) = split (":",$_);
		# not interested in monlist & intlist
		if (! $seen{$token}++ )
		{
			push @farray, "$token:$monlist:$intlist:$platform:$pushstate";
		}
		 
		
	}
	return @farray;
	
	
}
# Checks if the monitor for which
# an alarm occurred is part of the monitor list
# for that connection
sub getInterval
{
	my $intlist = shift;
	my $monlist = shift;
	my $mid = shift;

	#print ("getInterval:MID:$mid INT:$intlist AND MON:$monlist\n");
	my @ints = split (',',$intlist);
	my @mids = split (',',$monlist);
	my $idx = -1;
	foreach (@mids)
	{
		$idx++;
		#print ("Comparing $mid with $_\n");
		if ($mid eq $_)
		{
			last;
		}
	}
	#print ("RETURNING index:$idx with Value:".$ints[$idx]."\n");
	return $ints[$idx];
	
}
# Checks if the monitor for which
# an alarm occurred is part of the monitor list
# for that connection
sub isInList
{
	my $monlist = shift;
	my $mid = shift;

	my @mids = split (',',$monlist);
	my $found = 0;
	foreach (@mids)
	{
		if ($mid eq $_)
		{
			$found = 1;
			last;
		}
	}
	return $found;
	
}

sub getIdentity
{
	my $obj=shift;
	my $identity="";
	if (exists $obj->{conn} )
	{
		$identity = $obj->{conn}->ip().":".$obj->{conn}->port();
	}
	if ($obj->{token})
	{
		$identity=$identity." token ending in:...". substr($obj->{token},-10);
	}
	$identity="(unknown)" if (!$identity);
	return $identity;
}
	

# This is really the main module
# It opens a WSS socket and keeps listening
sub initSocketServer
{
	checkEvents();
	testProxyURL() if ($usePushProxy);

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
			apnsFeedbackCheck() if ($usePushAPNSDirect);
			testProxyURL() if ($usePushProxy);
			my $ac = scalar @active_connections;
			if (checkEvents())
			{
				Info ("Broadcasting new events to all $ac websocket clients\n");
					my ($serv) = @_;
					my $i = 0;
					foreach (@active_connections)
					{
						# Let's see if this connection is interested in this alarm
						my $monlist = $_->{monlist};
						my $intlist = $_->{intlist};
						my $last_sent = $_->{last_sent};
						my $obj = $_;
						my $connid = getIdentity($obj);
						Info ("Checking alarm rules for $connid");
						# we need to create a per connection array which will be
						# a subset of main events with the ones that are not in its
						# monlist left out
						my @localevents = ();
						foreach (@events)
						{
							if ($monlist eq "" || isInList($monlist, $_->{MonitorId} ) )
							{
								my $mint = getInterval($intlist, $monlist, $_->{MonitorId});
								my $elapsed;
								if ($last_sent->{$_->{MonitorId}})
								{
									 $elapsed = time() -  $last_sent->{$_->{MonitorId}};
									 if ($elapsed >= $mint)
									{
										Info("Monitor ".$_->{MonitorId}." event: sending this out as $elapsed is >= interval of $mint");
										push (@localevents, $_);
										$last_sent->{$_->{MonitorId}} = time();
									}
									else
									{
										
										 Info("Monitor ".$_->{MonitorId}." event: NOT sending this out as $elapsed is less than interval of $mint");
									}

								}
								else
								{
									# This means we have no record of sending any event to this monitor
									$last_sent->{$_->{MonitorId}} = time();
									Info("Monitor ".$_->{MonitorId}." event: last time not found, so sending");
									push (@localevents, $_);
								}

							}

						}
						# if this array is empty that means none of the alarms 
						# were generated from a monitor it is interested in
						next if (scalar @localevents == 0);

						my $str = encode_json({event => 'alarm', type=>'', status=>'Success', events => \@localevents});
						my $sup_str = encode_json({event => 'alarm', type=>'', status=>'Success', supplementary=>'true', events => \@localevents});
						my %hash_str = (event => 'alarm', status=>'Success', events => \@localevents);
						$i++;
						# if there is APNS send it over APNS
						# if not, send it over Websockets 
						# also disabled is a special state which means its registered over push
						# but it still wants messages over websockets - zmNinja sets this
						# when websockets override is enabled
						if (($_->{token} ne "") && ($_->{pushstate} ne "disabled" ))
						{
							if ($usePushProxy)
							{
								Info ("Sending notification over PushProxy");
								sendOverPushProxy($_,$alarm_header, $str) ;		
							}
							elsif ($usePushAPNSDirect)
							{

								Info ("Sending notification directly via APNS");
								sendOverAPNS($_,$alarm_header, \%hash_str) ;
							}
							# send supplementary event data over websocket
							if ($_->{pending} == VALID_WEBSOCKET)
							{
								if (exists $_->{conn})
								{
									Info ($_->{conn}->ip()."-sending supplementary data over websockets\n");
									eval {$_->{conn}->send_utf8($sup_str);};
									if ($@)
									{
								
										$_->{pending} = INVALID_WEBSOCKET;
									}
								}
							}

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
		# called when a new connection comes in
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
								   monlist => "",
								   intlist => "",
								   last_sent=>{},
								   platform => "websocket",
								   pushstate => '',
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
