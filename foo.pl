use JSON;
use Data::Dumper;

my $es_rules_file='/var/lib/zmeventnotification/es_rules.json';
open ($fh, "<", $es_rules_file );
my $data = do { local $/=undef; <$fh> };
eval {$hr = decode_json($data);};
%es_rules = %$hr;
#print Dumper(\%es_rules);


my $id=8;



my $foo_ref = $es_rules{notifications}->{monitors}->{$id}->{rules};
foreach my $rule (@{$foo_ref}) {
	print ("---HERE---\n");
	print Dumper($rule);
}



