#!perl -w

use strict;
use warnings;
$main::VERSION = "1.0";
use Getopt::Long qw(:config auto_version auto_help); # https://metacpan.org/pod/Getopt::Long
use YAML::PP; # https://metacpan.org/pod/YAML::PP
use YAML::PP::Common qw/ :PRESERVE /;
use JSON::PP; # https://metacpan.org/pod/JSON::PP
use Data::Dumper;

use Pod::Usage; # See __END__ for these options
my $prefixes = "prefixes.ttl";
my $secret;
my $index = "index";
my $opt_dump;
my $opt_yaml;
my $opt_json;
GetOptions
  ("secret=s" => \$secret,
   "index=s"  => \$index,
   "dump"     => \$opt_dump,
   "yaml"     => \$opt_yaml,
   "json"     => \$opt_json)
  or pod2usage(2);
my $infile = shift or
  warn "input.yaml not specified\n"
  and pod2usage(2);

my $input;
{open INFILE, $infile or die "can't find $infile: $!\n";
 local $/ = undef;
 $input = <INFILE>;
 close INFILE;
}
$input =~ s{\\$secret}{$secret}g if $secret;

our %prefix;
open PREFIXES, $prefixes or die "can't find $prefixes\n";
while (<PREFIXES>) {
  m{^\@prefix +(.*?): +<(.*?)> *\.} and $prefix{$1} = $2;
};
our $prefix_re = "(".join("|",keys(%prefix))."):";

my $yaml = YAML::PP->new
  (schema   => ['JSON'], # only allow true/false as boolean values
   header   => 0, # don't print "---" at start
   # preserve => PRESERVE_ORDER, # order of hash keys: unfortunately there's no way to sort them
);
my $obj = $yaml->load_string($input) or die "$!\n";

my @types = map {replacePrefixes($_,"types $obj->{types}")} split(/[, ]+/, $obj->{types});
$obj->{types} = [@types];
processFields($obj->{fields}) if exists $obj->{fields};

$opt_dump and print Dumper($obj) and exit;
$opt_yaml and print $yaml->dump_string($obj) and exit;

my $json = JSON::PP->new->pretty->canonical; # sort keys, use indentation
my $output = $json->encode ($obj);
$opt_json and print $output and exit;

my $sparql = <<"SPARQL";
PREFIX elastic:      <http://www.ontotext.com/connectors/elasticsearch#>
PREFIX elastic-inst: <http://www.ontotext.com/connectors/elasticsearch/instance#>
INSERT DATA {
  elastic-inst:$index elastic:createConnector '''
$output
''' .
}
SPARQL
print $sparql;

sub replacePrefixes {
  my $var = shift;
  my $context = shift;
  $var =~ s{$prefix_re}{
    exists $prefix{$1} or die "Prefix $1 is undefined but is used in $context\n";
    $prefix{$1}
  }e;
  $var
}

sub processFields {
  my $fields = shift;
  my @extraFields;
  foreach my $prop (@$fields) {
    my $name = $prop->{fieldName} or next;
    my $propertyChain = $prop->{propertyChain} or next;
    my @alternatives = split(/ *\| */,$propertyChain);
    my $n = $#alternatives ? 1 : undef; # if more than 1, we need to split name to name$1, name$2 ...
    foreach my $chain (@alternatives) {
      my @chain = map {replacePrefixes($_, "propertyChain $propertyChain")} split (/ *\/ */, $chain);
      my $prop_new;
      if ($n && $n>1) { # make a copy (since all characteristics must be the same) and save it as an "extra field"
        $prop_new = {%$prop};
        push(@extraFields, $prop_new);
      } else {
        $prop_new = $prop
      };
      $prop_new->{fieldName} = "$name\$$n" if $n;
      $prop_new->{propertyChain} = [@chain];
      $n++ if $n;
    };
    processFields($prop->{objectFields}) if exists $prop->{objectFields};
  };
  push(@$fields, @extraFields) if @extraFields;
}

__END__

=head1 index-yaml-json-sparql.pl

Convert GraphDB Elastic index definition from YAML to JSON and embed in SPARQL

=head1 SYNOPSIS

perl -S index-yaml-json-sparql.pl [options] input.yaml

  Options (can abbreviate to first letter):
    --help       Print this help
    --version    Print version number and exit
    --prefixes=  Prefixes to use to expand RDf properties YAML (default prefixes.ttl)
    --secret=    Replace $secret in YAML (typically the value of elasticsearchBasicAuthPassword)
    --index=     Index instance name (default "index")
    --dump       Print internal data structure after YAML parsing for debugging
    --yaml       Print expanded YAML for debugging
    --json       Print JSON (by default, JSON is embedded in SPARQL)
