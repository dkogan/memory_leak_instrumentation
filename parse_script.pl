#!/usr/bin/perl

use strict;
use warnings;


use feature 'say';

use bigint 'hex'; # to use a version of hex() that can handle very wide integers
                  # I'm going to see

# the context, indexed on the PID. The elements are
#   $Nbytes_allocated
#   %allocated;
#   ($prev_addr, $prev_ret, $prev_type, $prev_realloc0, $prev_realloc0_addr, $prev_realloc0_bytes);
#   $allocating;
my %contexts;


while(<>)
{
    next unless /probe_libc:([^:]+)/;
    my $type = $1;
    my $ret = $type =~ /_ret/;
    $type =~ s/_(?:ret(?:__return)?|[0-9]+)$//;

    my ($pid) = /^\S+\s+(\d+)/ or die
      "Couldn't parse PID from '$_'";

    my $newctx = 0;
    if (!exists $contexts{$pid})
    {
        $contexts{$pid} = { Nbytes_allocated => 0,
                            allocated        => {} };
        $newctx = 1;
    }
    my $ctx = $contexts{$pid};

    if ( $ret && !( !$ctx->{prev_ret} && $type eq $ctx->{prev_type}) &&
         !($ctx->{prev_realloc0} && $ctx->{prev_type} eq 'malloc' && $ctx->{prev_ret} && $type eq 'realloc') ) {

        # This should never happen, but sometimes it does. So I just ignore it
        # die "PID $pid: $type ret, but prev wasn't a corresponding !ret";
        next;
    }
    elsif ( !$ret && !$ctx->{prev_ret} &&
            !($ctx->{prev_realloc0} && $ctx->{prev_type} eq 'realloc' && !$ctx->{prev_ret} && $type eq 'malloc') &&
            !$newctx) {
        die "PID $pid: $type !ret following another !ret";
    }
    elsif ( $ctx->{prev_realloc0} && !($type eq 'malloc' || $type eq 'realloc'))
    {
        die "PID $pid: realloc(0, N) must be followed by malloc(N)";
    }
    elsif ( !$ret )
    {
        if ($type eq 'malloc' && /bytes=([0-9a-z]+)/)
        {
            $ctx->{allocating} = hex $1;
            if ( $ctx->{prev_realloc0} && $ctx->{allocating} != $ctx->{prev_realloc0_bytes} )
            {
                die "PID $pid: realloc(0, N) must be followed by malloc(N)";
            }
        }
        elsif ($type eq 'calloc' && /elem_size=([0-9a-z]+).*n=([0-9a-z]+)/)
        {
            $ctx->{allocating} = (hex $1) * (hex $2);
        }
        elsif ($type eq 'aligned_alloc' && /bytes=([0-9a-z]+)/)
        {
            $ctx->{allocating} = hex $1;
        }
        elsif ($type eq 'realloc' && /oldmem=([0-9a-z]+).*bytes=([0-9a-z]+)/)
        {
            if ( hex($1) == 0 )
            {
                # realloc(0, xxx) is always mapped to a malloc apparently. I treat
                # this specially
                $ctx->{prev_realloc0}       = 1;
                $ctx->{prev_realloc0_bytes} = hex $2;
            }
            else
            {
                $ctx->{allocating} = hex $2;
                $ctx->{prev_addr} = $1;
            }
        }
        elsif ($type eq 'free' && /mem=([0-9a-z]+)/)
        {
            if ( hex($1) != 0)  # free(0) does nothing
            {
                if (!defined $ctx->{allocated}{$1})
                {
                    say "Unallocated free at $1. Line $.";
                }
                else
                {
                    $ctx->{Nbytes_allocated} -= $ctx->{allocated}{$1}{bytes};
                    delete $ctx->{allocated}{$1};
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
            die "PID $pid: Ret didn't get arg1";
        }

        my $addr = $1;

        if ( hex($addr) == 0 )
        {
            say "$type returned NULL. Giving up";
            exit;
        }
        elsif ( $type =~ /^(?:[cm]alloc|aligned_alloc)$/ )
        {
            if (defined $ctx->{allocated}{$addr})
            {
                say "Double alloc at $addr. Line $.";
            }
            else
            {
                $ctx->{allocated}{$addr}{bytes} = $ctx->{allocating};
                $ctx->{allocated}{$addr}{line} = $.;
                $ctx->{Nbytes_allocated} += $ctx->{allocating};
            }

            if ( $ctx->{prev_realloc0} && $type eq 'malloc')
            {
                $ctx->{prev_realloc0_addr} = $addr;
            }
        }
        elsif ( $type eq 'realloc' )
        {
            if ( $ctx->{prev_realloc0} )
            {
                if ( $addr ne $ctx->{prev_realloc0_addr} )
                {
                    die "PID $pid: realloc(0, N) must be followed by malloc(N); differing addr";
                }

                $ctx->{prev_realloc0}       = undef;
                $ctx->{prev_realloc0_addr}  = undef;
                $ctx->{prev_realloc0_bytes} = undef;
            }
            else
            {
                my $prev0 = (hex($ctx->{prev_addr}) == 0);

                if (!$prev0 && !defined $ctx->{allocated}{$ctx->{prev_addr}})
                {
                    say "realloc not alloced at $ctx->{prev_addr}. Line $.";
                    $prev0 = 1;
                }

                if ($addr ne $ctx->{prev_addr} && defined $ctx->{allocated}{$addr})
                {
                    say "Double realloc at $addr. Line $.";
                }

                if ( !$prev0 )
                {
                    $ctx->{Nbytes_allocated} -= $ctx->{allocated}{$ctx->{prev_addr}}{bytes};
                    delete $ctx->{allocated}{$ctx->{prev_addr}};
                }

                $ctx->{allocated}{$addr}{bytes} = $ctx->{allocating};
                $ctx->{allocated}{$addr}{line} = $.;
                $ctx->{Nbytes_allocated} += $ctx->{allocating};
            }
        }
        else
        {
            say "Unknown ret line: '$_'";
            exit;
        }


        $ctx->{allocating} = undef;
    }

    $ctx->{prev_type} = $type;
    $ctx->{prev_ret}  = $ret;
}


for my $pid ( keys %contexts )
{
    my $ctx = $contexts{$pid};

    say "============== PID $pid =============";

    $ctx->{Nbytes_allocated} /= 1e6;
    say "Total allocated: $ctx->{Nbytes_allocated} MB";
    say '';

    for my $addr ( sort { $ctx->{allocated}{$a}{line} <=> $ctx->{allocated}{$b}{line}} keys %{$ctx->{allocated}} )
    {
        my ($bytes,$line) = ($ctx->{allocated}{$addr}{bytes},
                             $ctx->{allocated}{$addr}{line});
        say "Leaked " . sprintf('%5d', $bytes) . " bytes at line $line ($addr)";
    }
}
