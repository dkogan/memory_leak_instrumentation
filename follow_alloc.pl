#!/usr/bin/perl
use strict;
use warnings;

use Getopt::Euclid;
use feature ':5.10';

my $size = sprintf('0x%x', $ARGV{'<size>'} =~ /^0x/ ? hex($ARGV{'<size>'}) : $ARGV{'<size>'} );


my $next_after_alloc_type;
my %addrs;

my $refcount = 0;

my $printing;

while(<>)
{
    if(/^$/)
    {
        print "\n" if $printing;
        $printing = undef;
        next;
    }

    if( $printing && /^\s/ )
    {
        print;
        next;
    }


    next unless /probe_libc:([^:]+)/;

    if( /$size\b/ )
    {
        if(/realloc/)
        {
            die "realloc not supported";
        }

        my $type = /probe_libc:([a-z_]+)/;
        ($next_after_alloc_type) = $type;

        # I don't print allocation entries. Those aren't interesting. Allocation
        # EXITS are interesting and I print those further down
        # doprint();
    }
    elsif( $next_after_alloc_type )
    {
        my $type = /probe_libc:([a-z_]+)/;
        if($type ne $next_after_alloc_type)
        {
            die "Didn't get ret for type $type";
        }

        my ($addr) = /arg1=(0x[0-9a-f]+)/;
        $addrs{$addr} = 1;

        $next_after_alloc_type = undef;

        $refcount++;

        doprint();
        next;
    }
    else
    {
        for my $addr(keys %addrs)
        {
            if(/$addr\b/)
            {
                if(/free|realloc/)
                {
                    $refcount--;
                }

                delete $addrs{$addr};
                doprint();
            }
        }
    }
}

sub doprint
{
    $printing = 1;
    print "Line: $. Refcount: $refcount. $_";
}



=head1 NAME

follow_alloc.pl - trace allocation of a particular size

=head1 SYNOPSIS

 $ ./follow_alloc.pl --size 0x1234

=head1 DESCRIPTION

Looks at C<perf script> output to follow allocations of a particular size. This
is a filter for C<perf script> output, and reports data in the same format, but
cut down to include only matching data.

A C<realloc> to the desired size is not currently supported, and the script will
barf. I stop following C<realloc>s from the desired size, so those may end up
leaking without me knowing.

=head1 REQUIRED ARGUMENTS

=over

=item <size>

Size of allocation to trace

=for Euclid:
  size.type: /0x[0-9a-f]+|[0-9]+/

=back

=head1 AUTHOR

Dima Kogan, C<< <dima@secretsauce.net> >>
