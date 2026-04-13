
package Devel::Bug;

use v5.30;
use utf8;
use warnings;

use Term::ANSIColor; 
use Term::Size::Perl;

use List::Util qw(pairmap);
use Carp qw(croak carp);

use Data::Dump;


use constant BUG_OPTIONS => {
    out      => '',
    package  => '',
    filename => '',
    lineno   => '',
    val      => '*',
};

use constant ALIAS_OPTIONS => {
    output => 'out',
    pkg    => 'package',
    fn     => 'filename',
    line   => 'lineno',
};

use constant USE_OPTIONS => { BUG_OPTIONS->%*, bug => '' };

sub validate { 
    my $params= shift;

    pairmap {
        my $a= lc $a;
        $a= ALIAS_OPTIONS->{$a} if exists ALIAS_OPTIONS->{$a};

        exists $params->{$a} or croak qq(Unknown option '$a');
        $params->{$a} eq '*' or $params->{$a} eq ref($b) or croak qq(Option '$a' may not be type '@{[ ref($b) || '(SCALAR)' ]}');

        $a => $b;
    } @_;
}


our %OPTIONS;

sub import {
    shift;

    %OPTIONS= ( out => *STDERR, validate USE_OPTIONS, @_ );

    my $bug= 'bug';

    if (exists $OPTIONS{bug}) {
        # Don't export anything if explicity set to falsy.
        $bug= $OPTIONS{bug} or return;

        # Export bug under a different name.
        $bug=~/^ ( [a-z]\w* | _\w+ ) $/nix or croak qq(Illegal characters in 'bug' override subroutine name '$bug');
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

sub bug :lvalue {   # ($label= '', key/val paired options)
    # Pop an even number of key/val pairs from tail of list to init object.
    my $self= bless { %OPTIONS, validate BUG_OPTIONS, splice @_, @_ & 1 }, __PACKAGE__;

    # Get sigil/label string, if there is one.
    $self->{label}= shift // '';
    $self->{sigil}= $self->{label}=~s{^[@%]?}{} && $&;

    # Get extra info to include with output.
    my %info;

    @info{ qw(package filename lineno) }= caller;
    $info{lineno}= "line $info{lineno}";

    $self->{info}= join(' ', map { $self->{$_}? $info{$_} : () } qw(package filename lineno));

    # Tie an array or scalar, for list or scalar context respectively.
    if (wantarray) {
        $self->{data}= [];

        tie my @a, __PACKAGE__, $self;
        return @a;
    } else {
        $self->{sigil} and croak qq(Sigil '$self->{sigil}' used in scalar context);
        $self->{data}= \do { my $scalar };

        tie my $s, __PACKAGE__, $self;
        return $s;
    }
}

sub TIESCALAR { $_[1] }
sub TIEARRAY  { $_[1] }

sub CLEAR     { $_[0]->{data}= [] }
sub EXTEND    { $_[0]->{count}= $_[1] }
sub FETCH     { (@_ == 1)? $_[0]->{data}->$* : $_[0]->{data}[ $_[1] ] }

sub STORE {
    my $self=     $_[0];
    my $sigil=    $self->{sigil};
    my $data=     $self->{data};

    my $isScalar= @_ == 2;                              # was STORE called for SCALAR or ARRAY?
    my $override= exists $self->{val};
    my $width=    (Term::Size::Perl::chars $self->{out})[0];    # If not a terminal, $width is 0

    my sub sayVal {
        my $x= shift;
        my $txt;

        my sub valText {
            my $color= shift;
            my $label= $self->{label};
            my $info=  $self->{info};
            my $ml=    shift? "\n" : '';
            my $txt;

            my sub cv {
                my $txt= ref($_[0])? Data::Dumper::pp($_[0]) : $_[0];
                # $_[0]= Data::Dumper::pp($_[0]) if ref $_[0];
                # $color? colored($_[0], 'red on_grey23') : $_[0]
                $color? colored($txt, 'red on_grey23') : $txt;
            }

            my $items= 
                join $ml || ' ',
                map { $ml? "  $_" : $_ }    # multiline?
                        ($override)?     ( cv $self->{val}                         )  # override value specified
                    :   ($isScalar)?     ( cv $$data                               )  # data is scalar
                    :   ($sigil eq '@')? ( map cv($_), @$data                      )  # data is list: output grouped
                    :   ($sigil eq '%')? ( pairmap { cv($a).' => '.cv($b) } @$data )  # data is list of keys/value pairs: output grouped
                    :                    ( cv $data->[$x]                          ); # data is list: output as individual items

            $label.= '['.($color? colored($x, 'red') : $x).']'      if defined $x;

            $info=  $color? colored($info, 'bold').': ' : "$info: " if length $info;
            $label= $color? colored($label, 'bold').'=' : "$label=" if length $label;

            $txt.= $info.$label;
            $txt.= ($ml or not $color)? "($ml$items$ml)" : "$ml$items$ml";
        }

        $txt= valText;                                      # get plain text
        $txt= valText(1, length($txt) > $width) if $width;  # get colored terminal text, accounting for width

        say { $self->{out} } $txt;
    }

    if ($isScalar)
    {
        $$data= $_[1];
        sayVal;
    } else {
        my $x=       $_[1];
        $data->[$x]= $_[2];

        ($sigil or $override)
        ?   --$self->{count} == 0 && sayVal
        :   sayVal($x);
    }
}


# Catch if user code attempts to use this like a regular object.
sub AUTOLOAD {
    our $AUTOLOAD;
    die qq(Attempt to call unneeded non-existent subroutine '$AUTOLOAD': class @{[ __PACKAGE__ ]} intended for inline logging only);
}

# Prevent AUTOLOAD from getting called for DESTROY.
sub DESTROY { }



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

