#!/bin/zsh

# n is the first argument, if given, otherwise a large number
n=${1:-100000}

for (( i=0;i<$n;i++ )) { timeout 1 ./client.sh; sleep 1; }
