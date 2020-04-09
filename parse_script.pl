#!/usr/bin/perl

use strict;
use warnings;


use feature 'say';
use bigint;


# the context, indexed on the PID. The elements are
#   %allocated;
#   ($prev_addr, $prev_ret, $prev_type, $prev_realloc0_addr, $prev_realloc0_bytes);
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
        $contexts{$pid} = { allocated   => {},
                            doublealloc => [],
                            realloc0    => []};
        $newctx = 1;
    }
    my $ctx = $contexts{$pid};

    if ( defined $ctx->{prev_realloc0_bytes} && !($type eq 'malloc' || $type eq 'realloc'))
    {
        die "PID $pid: realloc(0, N) must be followed by malloc(N)";
    }


    my $prev_type = $ctx->{prev_type};
    my $prev_ret  = $ctx->{prev_ret};

    $ctx->{prev_type} = $type;
    $ctx->{prev_ret}  = $ret;

    if ( !$ret )
    {
        # this is a function CALL

        if ( # last call cycle should have been a RETURN of some function
             !$prev_ret &&

             # unless some complex realloc(0) logic is kicking in
             !(defined $ctx->{prev_realloc0_bytes} && $prev_type eq 'realloc' && !$prev_ret && $type eq 'malloc') &&
            !$newctx)
        {
            # This should never happen, but sometimes it does. So I just ignore
            # the issue and process the event anyway
            say "PID $pid line $.: $type !ret following another !ret";
        }

        if ($type eq 'malloc' && /bytes=((?:0x)?[0-9a-z]+)/)
        {
            $ctx->{allocating} = parsevalue($1);
            if ( defined $ctx->{prev_realloc0_bytes} && $ctx->{allocating} != $ctx->{prev_realloc0_bytes} )
            {
                die "PID $pid: realloc(0, N) must be followed by malloc(N)";
            }
        }
        elsif ($type eq 'calloc' && /elem_size=((?:0x)?[0-9a-z]+).*n=((?:0x)?[0-9a-z]+)/)
        {
            $ctx->{allocating} = parsevalue($1) * parsevalue($2);
        }
        elsif ($type eq 'aligned_alloc' && /bytes=((?:0x)?[0-9a-z]+)/)
        {
            $ctx->{allocating} = parsevalue($1);
        }
        elsif ($type eq 'realloc' && /oldmem=((?:0x)?[0-9a-z]+).*bytes=((?:0x)?[0-9a-z]+)/)
        {
            if ( parsevalue($1) == 0 )
            {
                # realloc(0, xxx) is always follows by a malloc() apparently.
                # and realloc(0, xxx) doesn't return. I handle this specially

                say("Saw realloc(0); this is complex logic that I don't trust to have gotten right. Skipping");
                push @{$ctx->{realloc0}}, [parsevalue($2),
                                           $.];
                $ctx->{prev_ret} = 1; # won't act on the return of this thing
                next;

                $ctx->{prev_realloc0_bytes} = parsevalue($2);
            }
            else
            {
                $ctx->{allocating} = parsevalue($2);
                $ctx->{prev_addr}  = parsevalue($1);
            }
        }
        elsif ($type eq 'free' && /mem=((?:0x)?[0-9a-z]+)/)
        {
            my $mem = parsevalue($1);
            if ( $mem != 0)  # free(0) does nothing
            {
                if (!defined $ctx->{allocated}{$mem})
                {
                    say "PID $pid: Unallocated free at $1. Line $.";
                }
                else
                {
                    delete $ctx->{allocated}{$mem};
                }
            }

            $ctx->{prev_ret} = $ret; # free has no free-ret so I set that now
        }
        else
        {
            say "PID $pid: Unknown !ret line: '$_'";
            exit;
        }
    }
    else
    {
        # this is a function RETURN

        if ( # last call cycle should have been a CALL of this same function
             !( !$prev_ret && $type eq $prev_type) &&

             # unless some complex realloc(0) logic is kicking in
            !(defined $ctx->{prev_realloc0_bytes} && $prev_type eq 'malloc' && $prev_ret && $type eq 'realloc') )
        {

            # This should never happen, but sometimes it does. So I just ignore it
            say "PID $pid line $.: $type ret, but prev wasn't a corresponding !ret";
            next;
        }

        if ( !/arg1=((?:0x)?[0-9a-z]+)/ )
        {
            die "PID $pid: Ret didn't get arg1";
        }

        my $addr = parsevalue($1);

        if ( $addr == 0 )
        {
            say "PID $pid: $type returned NULL... Pretending that this is ok.";
        }

        if ( $type =~ /^(?:[cm]alloc|aligned_alloc)$/ )
        {
            if (defined $ctx->{allocated}{$addr})
            {
                say "PID $pid: Double alloc at $addr. Line $. (prev alloc on line $ctx->{allocated}{$addr}{line})";
                push @{$ctx->{doublealloc}}, [$addr,
                                              $ctx->{allocated}{$addr}{bytes},
                                              $ctx->{allocated}{$addr}{line}];
            }

            $ctx->{allocated}{$addr}{bytes} = $ctx->{allocating};
            $ctx->{allocated}{$addr}{line} = $.;

            if ( defined $ctx->{prev_realloc0_bytes} && $type eq 'malloc')
            {
                $ctx->{prev_realloc0_addr} = $addr;
            }
        }
        elsif ( $type eq 'realloc' )
        {
            if ( defined $ctx->{prev_realloc0_addr} )
            {
                if ( $addr != $ctx->{prev_realloc0_addr} )
                {
                    die "PID $pid: realloc(0, N) must be followed by malloc(N); differing addr";
                }

                $ctx->{prev_realloc0_addr}  = undef;
                $ctx->{prev_realloc0_bytes} = undef;
            }
            else
            {
                my $prev0 = ($ctx->{prev_addr} == 0);

                if (!$prev0 && !defined $ctx->{allocated}{$ctx->{prev_addr}})
                {
                    say "PID $pid: realloc not alloced at $ctx->{prev_addr}. Line $.";
                    $prev0 = 1;
                }

                if ($addr != $ctx->{prev_addr})
                {
                    if(defined $ctx->{allocated}{$addr})
                    {
                        say "PID $pid: Double realloc at $addr. Line $. (prev alloc on line $ctx->{allocated}{$addr}{line})";
                        push @{$ctx->{doublealloc}},
                          [$addr,
                           $ctx->{allocated}{$addr}{bytes},
                           $ctx->{allocated}{$addr}{line}];
                    }
                }

                if ( !$prev0 )
                {
                    delete $ctx->{allocated}{$ctx->{prev_addr}};
                }

                $ctx->{allocated}{$addr}{bytes} = $ctx->{allocating};
                $ctx->{allocated}{$addr}{line} = $.;
            }
        }
        else
        {
            say "PID $pid: Unknown ret line: '$_'";
            exit;
        }
    }
}


for my $pid ( keys %contexts )
{
    my $ctx = $contexts{$pid};

    say "============== PID $pid =============";

    for my $addr ( sort { $ctx->{allocated}{$a}{line} <=> $ctx->{allocated}{$b}{line}} keys %{$ctx->{allocated}} )
    {
        my ($bytes,$line) = ($ctx->{allocated}{$addr}{bytes},
                             $ctx->{allocated}{$addr}{line});
        say "Leaked " . sprintf('%5d bytes at line %d (0x%x)', $bytes, $line, $addr);
    }
    for my $doublealloc ( @{$ctx->{doublealloc}} )
    {
        my ($addr,$bytes,$line) = @$doublealloc;
        say "Leaked " . sprintf('%5d bytes at line %d (0x%x); double-alloc...', $bytes, $line, $addr);
    }
    for my $realloc0 ( @{$ctx->{realloc0}} )
    {
        my ($bytes,$line) = @$realloc0;
        say "Leaked " . sprintf('%5d', $bytes) . " bytes at line $line maybe. realloc0...";
    }
}


sub parsevalue
{
    my ($x) = (@_);

    return hex($x) if $x =~ /^0x(.*)/;
    return int($x);
}
