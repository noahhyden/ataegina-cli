## A fake-tool tag must ride in argv, not only env

pgrep -f sees only the command line, so the mockserver tag is passed as a trailing argv token; otherwise the SIGTERM-ignoring wrapper is invisible and the SIGKILL-escalation test passes falsely.
