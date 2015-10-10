#!/usr/bin/perl

use strict;
use warnings;


use feature 'say';


my $Nbytes_allocated = 0;
my %allocated;

my ($prev_addr, $prev_ret, $prev_type, $prev_realloc0, $prev_realloc0_addr, $prev_realloc0_bytes);
my $allocating;


while(<>)
{
    next unless /probe_libc:([^:]+)/;

    my $type = $1;
    my $ret = $type =~ /_ret$/;
    $type =~ s/_(?:ret|[0-9]+)$//;


    if ( $ret && !( !$prev_ret && $type eq $prev_type) &&
         !($prev_realloc0 && $prev_type eq 'malloc' && $prev_ret && $type eq 'realloc') ) {
        die "$type ret, but prev wasn't a corresponding !ret";
    }
    elsif ( !$ret && !$prev_ret &&
            !($prev_realloc0 && $prev_type eq 'realloc' && !$prev_ret && $type eq 'malloc') &&
            $. > 1) {
        die "$type !ret following another !ret";
    }
    elsif ( $prev_realloc0 && !($type eq 'malloc' || $type eq 'realloc'))
    {
        die "realloc(0, N) must be followed by malloc(N)";
    }
    elsif ( !$ret )
    {
        if ($type eq 'malloc' && /bytes=([0-9a-z]+)/)
        {
            $allocating = hex $1;
            if ( $prev_realloc0 && $allocating != $prev_realloc0_bytes )
            {
                die "realloc(0, N) must be followed by malloc(N)";
            }
        }
        elsif ($type eq 'calloc' && /elem_size=([0-9a-z]+).*n=([0-9a-z]+)/)
        {
            $allocating = (hex $1) * (hex $2);
        }
        elsif ($type eq 'aligned_alloc' && /bytes=([0-9a-z]+)/)
        {
            $allocating = hex $1;
        }
        elsif ($type eq 'realloc' && /oldmem=([0-9a-z]+).*bytes=([0-9a-z]+)/)
        {
            if ( hex($1) == 0 )
            {
                # realloc(0, xxx) is always mapped to a malloc apparently. I treat
                # this specially
                $prev_realloc0       = 1;
                $prev_realloc0_bytes = hex $2;
            }
            else
            {
                $allocating = hex $2;
                $prev_addr = $1;
            }
        }
        elsif ($type eq 'free' && /mem=([0-9a-z]+)/)
        {
            if ( hex($1) != 0)  # free(0) does nothing
            {
                if (!defined $allocated{$1})
                {
                    say "Unallocated free at $1. Line $.";
                }
                else
                {
                    $Nbytes_allocated -= $allocated{$1}{bytes};
                    delete $allocated{$1};
                }
            }

            $ret = 1;           # free has no free-ret so I set that now
        }
        else
        {
            say "Unknown !ret line: '$_'";
            exit;
        }
    }
    elsif ( $ret )
    {
        if ( !/arg1=([0-9a-z]+)/ )
        {
            die "Ret didn't get arg1";
        }

        my $addr = $1;

        if ( hex($addr) == 0 )
        {
            say "$type returned NULL. Giving up";
            exit;
        }
        elsif ( $type =~ /^(?:[cm]alloc|aligned_alloc)$/ )
        {
            if (defined $allocated{$addr})
            {
                say "Double alloc at $addr. Line $.";
            }
            else
            {
                $allocated{$addr}{bytes} = $allocating;
                $allocated{$addr}{line} = $.;
                $Nbytes_allocated += $allocating;
            }

            if ( $prev_realloc0 && $type eq 'malloc')
            {
                $prev_realloc0_addr = $addr;
            }
        }
        elsif ( $type eq 'realloc' )
        {
            if ( $prev_realloc0 )
            {
                if ( $addr ne $prev_realloc0_addr )
                {
                    die "realloc(0, N) must be followed by malloc(N); differing addr";
                }

                $prev_realloc0       = undef;
                $prev_realloc0_addr  = undef;
                $prev_realloc0_bytes = undef;
            }
            else
            {
                my $prev0 = (hex($prev_addr) == 0);

                if (!$prev0 && !defined $allocated{$prev_addr})
                {
                    say "realloc not alloced at $prev_addr. Line $.";
                    $prev0 = 1;
                }

                if ($addr ne $prev_addr && defined $allocated{$addr})
                {
                    say "Double realloc at $addr. Line $.";
                }

                if ( !$prev0 )
                {
                    $Nbytes_allocated -= $allocated{$prev_addr}{bytes};
                    delete $allocated{$prev_addr};
                }

                $allocated{$addr}{bytes} = $allocating;
                $allocated{$addr}{line} = $.;
                $Nbytes_allocated += $allocating;
            }
        }
        else
        {
            say "Unknown ret line: '$_'";
            exit;
        }


        $allocating = undef;
    }


    $prev_type = $type;
    $prev_ret = $ret;
}


$Nbytes_allocated /= 1e6;
say "Total allocated: $Nbytes_allocated MB";
say '';

for my $addr ( sort { $allocated{$a}{line} <=> $allocated{$b}{line}} keys %allocated )
{
    my ($bytes,$line) = ($allocated{$addr}{bytes},
                         $allocated{$addr}{line});
    say "Leaked " . sprintf('%5d', $bytes) . " bytes at line $line ($addr)";
}
