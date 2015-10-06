#!/bin/zsh

< $1 awk '$1=="Leaked" {print $6,$2}' | feedgnuplot --domain --points --xlabel 'Line number' --ylabel 'Leak (kB)'
