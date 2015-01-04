package HTML::Differences;

use strict;
use warnings;

use Exporter qw( import );
use HTML::TokeParser;
use Text::Diff qw( diff );

our @EXPORT_OK = qw( html_text_diff diffable_html );

sub html_text_diff {
    my $html1 = shift;
    my $html2 = shift;
    my %p     = @_;

    return diff(
        diffable_html( $html1, %p ),
        diffable_html( $html2, %p ),
        {
            CONTEXT => ( $p{context} || 2**31 ),
            STYLE => $p{style} || 'Table',
        },
    );
}

{
    my %dispatch = (
        D  => 'declaration',
        S  => 'start_tag',
        E  => 'end_tag',
        T  => 'text',
        C  => 'comment',
        PI => 'processing_instruction',
    );

    sub diffable_html {
        my $html = shift;
        my %p    = @_;

        my $accumulator = _HTMLAccumulator->new( $p{ignore_comments} );

        my $parser = HTML::TokeParser->new( ref $html ? $html : \$html );
        while ( my $token = $parser->get_token() ) {
            my $type   = shift @{$token};
            my $method = $dispatch{$type}
                or die "Unknown token type: $type";

            $accumulator->$method( @{$token} );
        }

        return $accumulator->html_as_arrayref();
    }
}

package    # hide from PAUSE
    _HTMLAccumulator;

use HTML::Entities qw( encode_entities );

sub new {
    my $class           = shift;
    my $ignore_comments = shift;

    return bless {
        ignore_comments => $ignore_comments,
        html            => [],
        in_pre          => 0,
    }, $class;
}

sub html_as_arrayref { $_[0]->{html} }

sub declaration {
    push @{ $_[0]->{html} }, $_[1];
}

sub start_tag {
    my $self = shift;
    my $tag  = shift;
    my $attr = shift;

    # Things like <hr/> give us "hr/" as the value of $tag.
    $tag =~ s{\s*/$}{};

    # And <hr /> gives us "/" as an attribute.
    delete $attr->{'/'};

    if ( $tag eq 'pre' ) {
        $self->{in_pre} = 1;
    }

    my $text = '<' . $tag;
    if ( $attr && %{$attr} ) {
        my @attrs;
        for my $key ( sort keys %{$attr} ) {
            my $quote = $attr->{$key} =~ /"/ ? q{'} : q{"};
            push @attrs,
                  $key . '='
                . $quote
                . encode_entities( $attr->{$key} )
                . $quote;
        }
        $text .= q{ } . join q{ }, @attrs;
    }
    $text .= '>';

    push @{ $self->{html} }, $text;
}

sub end_tag {
    my $self = shift;
    my $tag  = shift;

    if ( $tag eq 'pre' ) {
        $self->{in_pre} = 0;
    }

    push @{ $self->{html} }, '</' . $tag . '>';
}

sub text {
    my $self = shift;
    my $text = shift;

    unless ( $self->{in_pre} ) {
        return unless $text =~ /\S/;
        $text =~ s/^\s+|\s+$//g;
        $text =~ s/\s+/ /s;
    }

    push @{ $self->{html} }, $text;
}

sub comment {
    my $self = shift;

    return if $self->{ignore_comments};

    push @{ $self->{html} }, $_[0];
}

sub processing_instruction {
    my $self = shift;
    push @{ $self->{html} }, $_[0];
}

1;

# ABSTRACT: Use 
