#!/usr/bin/perl

use strict;
use warnings;
use feature 'say';

my $Nbytes_allocated = 0;
my %alloc;

while(<>)
{
    # skip backtrace for now
    next unless /^[a-z]/;

    my ($cmd, $arg1, $arg2, $ret) =
      /^(.*)\((-1|[0-9A-Z]+), (-1|[0-9A-Z]+)\) -> (-1|[0-9A-Z]+)$/;

    my ($alloc_size, $alloc_addr, $alloc_prev_addr);
    if( $cmd eq 'malloc' )
    {
        $alloc_size = hex($arg1);
        $alloc_addr = hex($ret);
    }
    elsif( $cmd eq 'calloc' )
    {
        $alloc_size = hex($arg1) * hex($arg2);
        $alloc_addr = hex($ret);
    }
    elsif( $cmd eq 'realloc' )
    {
        $alloc_prev_addr = hex($arg1);
        $alloc_size      = hex($arg2);
        $alloc_addr      = hex($ret);
    }
    elsif( $cmd eq 'posix_memalign' ||
           $cmd eq 'aligned_alloc')
    {
        $alloc_size = hex($arg2);
        $alloc_addr = hex($ret);
    }
    elsif( $cmd eq 'free' )
    {
        my $addr = hex($arg1) or next; # free(0) does nothing
        do_free( $addr );
        next;
    }
    else
    {
        die "Unknown cmd '$cmd' on line $.";
    }



    # we're allocating something
    if( $alloc_addr == 0 )
    {
        say "$cmd returned NULL on line $.. Giving up";
        exit;
    }
    if( !defined $alloc_prev_addr)
    {
        # not realloc
        do_malloc($alloc_size, $alloc_addr);
    }
    else
    {
        # realloc
        do_free($alloc_prev_addr);
        do_malloc($alloc_size, $alloc_addr);
    }
}


$Nbytes_allocated /= 1e6;
say "Total allocated: $Nbytes_allocated MB";
say '';

for my $addr ( sort { $alloc{$a}[1] <=> $alloc{$b}[1]} keys %alloc )
{
    my ($bytes,$line) = @{$alloc{$addr}};
    say "Leaked $bytes bytes at line $line";
}






sub do_free
{
    my ($addr) = @_;
    if (!defined $alloc{$addr})
    {
        say "Unallocated free at $addr. Line $.";
    }
    else
    {
        $Nbytes_allocated -= $alloc{$addr}[0];
        delete $alloc{$addr};
    }
}

sub do_malloc
{
    my ($size, $addr) = @_;

    if (defined $alloc{$addr})
    {
        say "Double alloc at $addr. Line $.";
    }
    else
    {
        $alloc{$addr} = [$size, $.];
        $Nbytes_allocated += $size;
    }
}
