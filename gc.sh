#!/bin/zsh

source reademacsvar.sh
$EMACS_CLIENT_CMD -a '' -e '(garbage-collect)'
