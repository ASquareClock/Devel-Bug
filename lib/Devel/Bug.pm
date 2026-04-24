
package Devel::Bug;

our $VERSION = '0.01';

use v5.8;
use utf8;

use strict;
use warnings;

use Term::ANSIColor; 
use Term::Size::Perl;

use Carp qw(croak);

use Data::Dump qw(pp);


use constant BUG_OPTIONS => {
    out         => '*',
    multiline   => '',
    infocolor   => '',
    labelcolor  => '',
    valcolor    => '',
    indices     => '',
    keyval      => '',
    package     => '',
    filename    => '',
    lineno      => '',
    val         => '*',
};

use constant ALIAS_OPTIONS => {
    output   => 'out',
    o        => 'out',
    ic       => 'infocolor',
    lc       => 'labelcolor',
    vc       => 'valcolor',
    ml       => 'multiline',
    m        => 'multiline',
    indexes  => 'indices',
    index    => 'indices',
    i        => 'indices',
    '@'      => 'indices',
    kv       => 'keyval',
    k        => 'keyval',
    '%'      => 'keyval',
    pkg      => 'package',
    p        => 'package',
    fn       => 'filename',
    f        => 'filename',
    line     => 'lineno',
    ln       => 'lineno',
    l        => 'lineno',
    value    => 'val',
    v        => 'val',
    override => 'val',
};

use constant USE_OPTIONS => {
    %{ +BUG_OPTIONS },
    bug => '',
};

use constant {
    PLAIN   => 0,
    COLORED => 1,
};

use constant CALLER_INFO => qw(package filename lineno);


sub _pairs {
    my $array= shift;
    my @list;

    for (my $i= 0; $i < @$array; $i+= 2) {
        push @list, [ $array->[$i] => $array->[$i + 1] ];
    }

    @list;
}


sub validate { 
    my $params= shift;

    @_ & 1 and croak qq(Odd number of elements in key => value option list);

    my @options;

   foreach (_pairs \@_) {
        my ($opt, $val)= ( lc($_->[0]) => $_->[1] );

        $opt= ALIAS_OPTIONS->{$opt} if exists ALIAS_OPTIONS->{$opt};

        exists $params->{$opt} or croak qq(Unknown option '$opt');
        $params->{$opt} eq '*' or $params->{$opt} eq ref($val) or croak qq(Option '$opt' may not be type '@{[ ref($val) || '(SCALAR)' ]}');

        push @options, $opt => $val;
    }

    @options;
}


my %OPTIONS;

sub import {
    shift;

    %OPTIONS= ( out => *STDERR, validate USE_OPTIONS, lc => 'bold', vc => 'red on_grey23', @_ );

    my $bug= 'bug';

    if (exists $OPTIONS{bug}) {
        # Don't export anything if explicity set to falsy.
        $bug= $OPTIONS{bug} or return;

        # Export bug under a different name.
        $bug=~/^ (?: [a-z]\w* | _\w+ ) $/ix or croak qq(Illegal characters in 'bug' override subroutine name '$bug');
        delete $OPTIONS{bug};
    }

    no strict 'refs';
    *{ caller.'::'.$bug }= \&bug;
}


# Debugging utility class.
#   Allows for inlining a temporary "bug" which will output intermediate expression data.
#   Ex:     my $infoPN= $CV_INFO_DIR."/".(bug('relpath')= substr($_, length($sourceDir) + 1));
#   Output: relpath=(...)

# To preserve list context, use form: (bug 'list')= ( some list );

sub bug :lvalue {   # ('label[:flags]', key/val paired options)
    # Get label and option flags.
    my $label= @_ & 1? shift : '';
    ($label, my $flags)= split /:/, defined($label)? $label : '', 2;
    unshift @_, map { $_ => 1 } split //, defined($flags)? $flags : '';

    # Pop an even number of key/val pairs from tail of list to init object.
    my $self= bless { %OPTIONS, validate BUG_OPTIONS, @_ }, __PACKAGE__;

    $self->{label}= defined($label)? $label : '';

    # Get extra info to include with output.
    my %info;

    @info{ +CALLER_INFO }= caller;
    $info{lineno}= "line $info{lineno}";

    $self->{info}= join(' ', map { $self->{$_}? $info{$_} : () } CALLER_INFO);

    # Tie an array or scalar, for list or scalar context respectively.
    if (wantarray) {
        $self->{data}= [];

        tie my @a, __PACKAGE__, $self;
        return @a;
    } else {
        $self->{data}= \do { my $scalar };
        # $self->{sigil} and croak qq(Sigil '$self->{sigil}' used in scalar context);

        tie my $s, __PACKAGE__, $self;
        return $s;
    }
}

sub TIESCALAR { $_[1] }
sub TIEARRAY  { $_[1] }

sub CLEAR     { $_[0]->{data}= [] }
sub EXTEND    { }

sub FETCHSIZE { scalar @{ $_[0]->{data} } }
sub STORESIZE { }

sub FETCH     { @_ == 1?  ${ $_[0]->{data} }         :  $_[0]->{data}[ $_[1] ]         }
sub STORE     { @_ == 2? (${ $_[0]->{data} }= $_[1]) : ($_[0]->{data}[ $_[1] ]= $_[2]) }

sub DESTROY {
    my $self=      $_[0];
    my $data=      $self->{data};
    my $multiline= $self->{multiline};
    my $indices=   $self->{indices} || '';
    my $keyval=    $self->{keyval};
    my $override=  exists $self->{val};
    my $termW=     (Term::Size::Perl::chars $self->{out})[0] || 0;
    my $isScalar=  ref($data) eq 'SCALAR';

    my ($ic, $lc, $vc)= @{$self}{ qw(infocolor labelcolor valcolor) };

    my $str;

    my $toString= sub {
        my $color= $_[0];
        my $ml=    $_[1] || $multiline || $indices? "\n" : '';

        my $label= $self->{label};
        my $info=  $self->{info};

        local $_;

        my $cv= sub {
            my $txt= ref $_[0]? Data::Dump::pp($_[0]) : defined $_[0]? $_[0] : 'UNDEF';
            $color && $vc? colored($txt, $vc) : $txt;
        };

        my $i= 0;

        my $vals= 
            join $ml || ' ',
                map { $ml? "  $_" : $_ }    # multiline?
                      $override? ( $cv->($self->{val}) ) 
                    : $isScalar? ( $cv->($$data) )
                    : $keyval?   ( map { ($indices && '['.$i++.'] ').$cv->($_->[0]).' => '.$cv->($_->[1]) } _pairs($data) ) 
                    :            ( map { ($indices && '['.$i++.'] ').$cv->($_) } @$data );

        $info=  $color && $ic? colored($info, $ic).': ' : "$info: " if length $info;
        $label= $color && $lc? colored($label, $lc).'=' : "$label=" if length $label;

        $_.= $info.$label;
        $_.= ($ml or not $color)? "($ml$vals$ml)" : "$ml$vals$ml";
        $_;
    };

    $str= $toString->(PLAIN);
    $str= $toString->(COLORED, $termW < length $str) if $termW;

    print { $self->{out} } $str."\n";
}


# Catch if user code attempts to use this like a regular object.
sub AUTOLOAD {
    our $AUTOLOAD;
    croak qq(Attempt to call unneeded non-existent subroutine '$AUTOLOAD': class @{[ __PACKAGE__ ]} intended for inline logging only);
}




1;


# Implemented. Keeping comment because it's a good use example.

# IDEA:
#   NOW:
#   subname($sub)=~/^.+(?=::)/
#   ?   do { say "\$&=($&)"; *{ $caller.'::'.$name }= \&{ $&.'::'.$name } }
#   :   carp qq(Unable to get package name from anonymous sub "@{[ subname($sub) ]}");
#
#   INSTEAD, let bug output something other than expression value (while still passing that through); convenient for flow:
#   subname($sub)=~/^.+(?=::)/
#   ?   bug($&)= *{ $caller.'::'.$name }= \&{ $&.'::'.$name }
#   :   carp qq(Unable to get package name from anonymous sub "@{[ subname($sub) ]}");

