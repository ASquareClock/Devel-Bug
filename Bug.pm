
package Devel::Bug;

use v5.30;

use utf8;

use warnings;

use Exporter 'import';
our @EXPORT= qw(bug);

use Term::ANSIColor; 
use Term::Size::Perl;

use List::Util qw(pairmap);
use Scalar::Util qw(reftype);


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

sub bug :prototype(;$) :lvalue ($label= '')
{
    my $label= shift // ''
    my $sigil= $label=~s{^[@%]?}{} && $&;
    
    if (wantarray)  { tie my @a, __PACKAGE__, $label, $sigil; return @a }
    else            { tie my $s, __PACKAGE__, $label, $sigil; return $s }
}

sub TIESCALAR($class, $label, $sigil)
{
    $sigil and die qq(Sigil '$sigil' used in scalar context);

    my $self= {};

    $self->{label}=    $label;
    $self->{data}=     \do { my $s };
    $self->{isScalar}= 1;

    bless $self, $class;
}

sub TIEARRAY($class, $label, $sigil)
{
    my $self= {};

    $self->{label}= $label;
    $self->{sigil}= $sigil;
    $self->{data}=  [];

    bless $self, $class;
}

sub CLEAR($self)
{
    $self->{data}= [];
}

sub EXTEND($self, $size)
{
    $self->{count}= $size if $self->{sigil};
}

sub FETCH($self, $x= undef)
{
    $self->{isScalar}
    ?   $self->{data}->$*
    :   $self->{data}[ $x ];
}


# sub bonny($node, $width= undef)
# {
#     my @stack= ( { node => $node, i => 0 } );

#     my $inner;
#     {
#         my $node= $stack[-1]{node};

#         if (defined $inner)
#         {
#             push $stack[-1]{text}->@*, $inner;
#             $inner= undef;
#         }

#         if (reftype($node) eq 'SCALAR')
#         {
#             push $stack[-1]{text}->@*, qq(\\"$$node");
            
#             $inner= $stack[-1]{text};
#             pop @stack;
#             redo if @stack;
#             last;
#         }

#         if (reftype($node) eq 'ARRAY')
#         {
#             my $i= $stack[-1]{i}++;

#             if ($i == 0)
#             {
#                 # push $stack[-1]{text}->@*, '@';
#                 # push $stack[-1]{text}->@*, '[ ';
#             }
#             elsif ($i == @$node)
#             {
#                 # push $stack[-1]{text}->@*, ' ]';

#                 $inner= $stack[-1]{text};
#                 pop @stack;
#                 redo if @stack;
#                 last;
#             }
#             else
#             {
#                 # push $stack[-1]{text}->@*, ', ';
#             }

#             my $val= $node->[$i];

#             unless (ref $val)
#             {
#                 push $stack[-1]{text}->@*, "'$val'";
#                 redo;
#             }
            
#             push @stack, { node => $val, i => 0 };

#             redo;
#         }

#         if (reftype($node) eq 'HASH')
#         {
#             my $keys= $stack[-1]{keys}||= [ keys %$node ];
#             my $i=    $stack[-1]{i}++;

#             if ($i == 0)
#             {
#                 # push $stack[-1]{text}->@*, '%';
#                 # push $stack[-1]{text}->@*, '{ ';
#             }
#             elsif ($i == @$keys)
#             {
#                 # push $stack[-1]{text}->@*, ' }';

#                 $inner= $stack[-1]{text};
#                 pop @stack;
#                 redo if @stack;
#                 last;
#             }
#             else
#             {
#                 # push $stack[-1]{text}->@*, ', ';
#             }
            
#             my $key= $keys->[$i];
#             my $val= $node->{$key};

#             unless (ref $val)
#             {
#                 push $stack[-1]{text}->@*, $key => $val;
#                 redo;
#             }

#             push $stack[-1]{text}->@*, $key;
#             push @stack, { node => $val, i => 0 };

#             redo;
#         }
#     }

#     @stack= ( { node => $inner, i => 0 } );

#     my $text;
#     {
#         my $node= $stack[-1]{node};
#         my $ind0= '  ' x $#stack;
#         my $ind1= '  ' x @stack;

#         if (reftype($node) eq 'ARRAY')
#         {
#             my $i= $stack[-1]{i}++;

#             if ($i == 0)
#             {
#                 $text.= "\n$ind0<\n";
#             }
#             elsif ($i == @$node)
#             {
#                 $text.= "\n$ind0>\n";

#                 pop @stack;
#                 redo if @stack;
#                 last;
#             }
#             else
#             {
#                 # $text.= ",\n";
#             }

#             my $val= $node->[$i];

#             unless (ref $val)
#             {
#                 $text.= "$ind1$val";
#                 redo;
#             }
            
#             push @stack, { node => $val, i => 0 };

#             redo;
#         }
#     }

#     $text;
# }

sub STORE
{
    our $self=  shift;
    our $sigil= $self->{sigil};
    our $data=  $self->{data};
    our $width= (Term::Size::Perl::chars)[0];

    sub sayVal
    {
        our $x= shift;

        sub valText
        {
            our $color= shift;
            my $label=  $self->{label};
            my $ml=     shift? "\n" : '';
            local $_;

            sub cv($val)
            {
                $val= pp($val) if ref $val;
                $color? colored($val, 'red on_grey23') : $val
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

