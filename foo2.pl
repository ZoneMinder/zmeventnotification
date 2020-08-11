use Time::Piece;

my $format = "%Y %I:%M %p";

my $date = Time::Piece->strptime("2020 4 am", $format);
print ($date);

my $now = Time::Piece->new->strftime($format);
$now = Time::Piece->strptime($now, $format);
print ("\n");
print ($now);

