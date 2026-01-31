package ZmEventNotification::DB;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(getAllMonitorIds updateEventinZmDB getNotesFromEventDB);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

sub getAllMonitorIds {
  return map { $_->{Id} } values(%main::monitors);
}

sub updateEventinZmDB {
  my ( $eid, $notes ) = @_;
  $notes = $notes . ' ';
  main::Debug(1, 'updating Notes clause for Event:' . $eid . ' with:' . $notes);
  my $sql = 'UPDATE Events SET Notes=CONCAT(?,Notes) WHERE Id=?';
  my $sth = $main::dbh->prepare_cached($sql)
    or main::Fatal( "UpdateEventInZmDB: Can't prepare '$sql': " . $main::dbh->errstr() );
  my $res = $sth->execute( $notes, $eid )
    or main::Fatal( "UpdateEventInZmDB: Can't execute: " . $sth->errstr() );
  $sth->finish();
}

sub getNotesFromEventDB {
  my $eid = shift;
  my $sql = 'SELECT `Notes` from `Events` WHERE `Id`=?';
  my $sth = $main::dbh->prepare_cached($sql)
    or main::Fatal( "getNotesFromEventDB: Can't prepare '$sql': " . $main::dbh->errstr() );
  my $res = $sth->execute($eid)
    or main::Fatal( "getNotesFromEventDB: Can't execute: " . $sth->errstr() );
  my $notes = $sth->fetchrow_hashref();
  $sth->finish();

  return $notes->{Notes};
}

1;
