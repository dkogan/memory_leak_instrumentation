#!/bin/zsh

source reademacsvar.sh

# read STDERR output, join single characters into lines, tee to a log file,
# separate temporal lulls with newlines
sudo unbuffer sysdig proc.name=${EMACS_CMD:t} -c stderr |& \
    perl -ne 'BEGIN { autoflush STDOUT; } if(length($_) == 2) { chomp; } print' | \
    tee /tmp/emacs.sysdig.log | \
    perl -M'Time::HiRes qw(gettimeofday tv_interval)' -pe 'BEGIN { autoflush STDOUT;} @t1 = gettimeofday; @t0 = @t1 unless @t0; $dt = tv_interval(\@t0, \@t1); print "\n" if $dt > 0.1; @t0 = @t1'
