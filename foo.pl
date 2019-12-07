my $res = `/var/lib/zmeventnotification/bin/post_event.sh`;
my $code = $? >> 8;
print ($res. " AND ".$code);

$res = `/var/lib/zmeventnotification/bin/post_event.sh`;
my $code = $? >> 8;
print ($res. " AND ".$code);
