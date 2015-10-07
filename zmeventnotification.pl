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


use strict;
use bytes;
use Net::WebSocket::Server;
use IO::Socket::SSL;
use Crypt::MySQL qw(password password41);
use JSON;

# ==========================================================================
#
# These are the elements you can edit to suit your installation
#
# ==========================================================================

use constant SLEEP_DELAY=>5; 			# duration in seconds after which we will check for new events
use constant MONITOR_RELOAD_INTERVAL => 300;
use constant EVENT_NOTIFICATION_PORT=>9000; 	# port for Websockets connection
use constant WEBSOCKET_AUTH_DELAY=>20; 		# max seconds by which authentication must be done
use constant SSL_CERT_FILE=>'/etc/apache2/ssl/zoneminder.crt';	 #needed for WSS to work
use constant SSL_KEY_FILE=>'/etc/apache2/ssl/zoneminder.key';

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

Info( "Event Notification daemon  starting\n" );

my $dbh = zmDbConnect();
my %monitors;
my $monitor_reload_time = 0;
my $wss;
my $evt_str="";
my @events=();
my @active_connections=();


initSocketServer();
Info( "Event Notification daemon exiting\n" );
exit();

sub checkEvents()
{

	my $eventFound = 0;
	$evt_str="";
	if ( (time() - $monitor_reload_time) > MONITOR_RELOAD_INTERVAL )
    	{
		Debug ("Reloading Monitors...\n");
		foreach my $monitor (values(%monitors))
		{
			zmMemInvalidate( $monitor );
		}
		loadMonitors();
	}

	@events = ();
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
				$evt_str = $evt_str.$monitor->{Name}.":".$monitor->{Id}.":".$last_event.",";
				my $name = $monitor->{Name};
				my $mid = $monitor->{Id};
				my $eid = $last_event;
				push @events, {Name => $name, MonitorId => $mid, EventId => $last_event};
				$eventFound = 1;
			}
			
		}
	}
	return ($eventFound);
}

sub loadMonitors
{
    Debug( "Loading monitors\n" );
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

sub checkConnection
{
	foreach (@active_connections)
	{
		my $curtime = time();
		if ($_->{pending} == '1')
		{
			if ($curtime - $_->{time} > WEBSOCKET_AUTH_DELAY)
			{
				my $conn = $_->{conn};
				Info ("Rejecting ".$conn->ip()." - authentication timeout");
				$_->{pending} = '-1';
				my $str = encode_json({status=>'Fail', reason => 'NOAUTH'});
				eval {$_->{conn}->send_utf8($str);};
				$_->{conn}->disconnect();
			}
		}

	}
	@active_connections = grep { $_->{pending} != '-1' } @active_connections;
}

sub checkMessage
{
	my ($conn, $msg) = @_;	
	my $json_string = decode_json($msg);
	my $uname = $json_string->{'data'}->{'user'};
	my $pwd = $json_string->{'data'}->{'password'};
	return if ($uname eq "" || $pwd eq "");
	foreach (@active_connections)
	{
		if (($_->{conn}->ip() eq $conn->ip())  &&
	            ($_->{conn}->port() eq $conn->port())  &&
		    ($_->{pending}='1'))
		{
			if (!validateZM($uname,$pwd))
			{
				my $str = encode_json({status=>'Fail', reason => 'BADAUTH'});
				eval {$_->{conn}->send_utf8($str);};
				Info("Bad authentication provided by ".$_->{conn}->ip());
			 	$_->{pending}='-1';
			}
			else
			{

			 	$_->{pending}='0';
				my $str = encode_json({status=>'Success', reason => ''});
				eval {$_->{conn}->send_utf8($str);};
				Info("Correct authentication provided by ".$_->{conn}->ip());
				
			}
		}
	}
}
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
			my $ac = $#active_connections;
			print ("ACTIVE CONNECTIONS: $ac \n");
			if (checkEvents())
			{
				Info ("Sending $evt_str to all websocket clients\n");
					my ($serv) = @_;
					my $str = encode_json({status=>'Success', events => \@events});
					foreach (@active_connections)
					{
						if ($_->{pending} == '0')
						{
							eval {$_->{conn}->send_utf8($str);};
						}
						
					}


			}
		},
		on_connect => sub {
			my ($serv, $conn) = @_;
			Info ("got a websocket connection from ".$conn->ip()."\n");
			$conn->on(
				utf8 => sub {
					my ($conn, $msg) = @_;
					Info ("got a message from ".$conn->ip()." saying: ".$msg);
					checkMessage($conn, $msg);
				},
				handshake => sub {
					my ($conn, $handshake) = @_;
					Info ("Websockets: New Connection Handshake requested from ".$conn->ip()." state=pending auth");
					my $connect_time = time();
					push @active_connections, {conn => $conn, pending => '1', time=>$connect_time};
					
				},
			);

			
		}
	)->start;
}
