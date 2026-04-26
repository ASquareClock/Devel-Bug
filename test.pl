#!/usr/bin/env perl

use v5.30;
use warnings;

use utf8;
use open IO => ':utf8', ':std';

# use Sub::Util qw(subname);
# use Scalar::Util qw(looks_like_number blessed weaken);

# use Carp qw(croak confess carp cluck);

# use Data::Dumper; $Data::Dumper::Indent= 1;
# use Data::Dump qw(pp);


use Devel::Bug ':l', out => *STDOUT;

say "=== Scalar Test ===";
my $result= (my $in= bug('scalar-test')= (100 - 3)) + 7;
say "Final scalar result: $result";

say "\n=== Simple List Test ===";
my @nums= (bug 'grouped-list-test')= (bug ':fi')= (10, 20, 30, 40);
say "List length: ", scalar @nums;

say "\n=== Key/Value List Test ===";
my %hash= (bug 'pairs-test:@%')= (alpha => 1, beta => 2, gamma => 3, delta => 4);
say "Hash has ", scalar(keys %hash), " keys";




exit 0;

