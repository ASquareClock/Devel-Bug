
package Devel::Bug;

use v5.30;
use utf8;
use warnings;

use Exporter 'import';
our @EXPORT= qw(bug);

use Term::ANSIColor; 
use Term::Size::Perl;

use List::Util  qw(pairmap);
use Scalar::Util qw(reftype);
use Carp qw(croak carp);


use Data::Dumper; $Data::Dumper::Indent= 1;
use Data::Dump qw(pp);



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



# Debugging utility class.
#   Allows for inlining a temporary "bug" which will output intermediate expression data.
#   Ex:     my $infoPN= $CV_INFO_DIR."/".(bug('relpath')= substr($_, length($sourceDir) + 1));
#   Output: relpath=(...)

# To preserve list context, use form: (bug 'list')= ( some list );

sub bug :prototype(;$) :lvalue  # ($label= '')
{
    my $label= shift // '';
    my $sigil= $label=~s{^[@%]?}{} && $&;
    
    if (wantarray)  { tie my @a, __PACKAGE__, $label, $sigil; return @a }
    else            { tie my $s, __PACKAGE__, $label, $sigil; return $s }
}

sub TIESCALAR   # ($class, $label, $sigil)
{
    $_[2] and croak qq(Sigil '$_[2]' used in scalar context);

    bless { label => $_[1], data => \do { my $s }, isScalar => 1 }, $_[0];
}

sub TIEARRAY    # ($class, $label, $sigil)
{
    bless { label => $_[1], sigil => $_[2], data => [] }, $_[0];
}

sub CLEAR   # ($self)
{
    $_[0]->{data}= [];
}

sub EXTEND  # ($self, $size)
{
    $_[0]->{count}= $_[1] if $_[0]->{sigil};
}

sub FETCH   # ($self, $x= undef)    Maybe could count args instead of isScalar test
{
    $_[0]->{isScalar}
    ?   $_[0]->{data}->$*
    :   $_[0]->{data}[ $_[1] ];
}

sub STORE
{
    my $self=  shift;
    my $sigil= $self->{sigil};
    my $data=  $self->{data};
    my $width= (Term::Size::Perl::chars)[0];

    my sub sayVal
    {
        my $x= shift;

        my sub valText
        {
            my $color= shift;
            my $label=  $self->{label};
            my $ml=     shift? "\n" : '';
            local $_;

            my sub cv
            {
                $_[0]= pp($_[0]) if ref $_[0];
                $color? colored($_[0], 'red on_grey23') : $_[0]
            }

            my $items= 
                join $ml || ' ',
                map $ml? "  $_" : $_,
                    $self->{isScalar}? ( cv $$data )
                :       ($sigil eq '@')? map cv($_), @$data
                    :   ($sigil eq '%')? pairmap { cv($a).' => '.cv($b) } @$data
                    :       ( cv $data->[$x] );

            $label.= '['.($color? colored($x, 'red') : $x).']' if defined $x;

            $_.= $color? colored($label, 'bold').'=' : "$label=" if length $label;
            $_.= ($ml or not $color)? "($ml$items$ml)" : "$ml$items$ml";
            $_;
        }

        local $_= valText;
        $_= valText(1, length > $width) if $width;

        say STDERR;
    }

    if ($self->{isScalar})
    {
        $$data= shift;
        sayVal;
    }
    else
    {
        my $x=       shift;
        $data->[$x]= shift;

        if ($sigil) { sayVal if --$self->{count} == 0 }
        else        { sayVal($x) }
    }
}


sub AUTOLOAD
{
    our $AUTOLOAD;

    die qq(Attempt to call unneeded non-existent subroutine '$AUTOLOAD': class @{[ __PACKAGE__ ]} intended for inline logging only);
}

sub DESTROY { }


1;

