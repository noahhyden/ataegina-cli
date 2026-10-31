## config set is limited to a key whitelist

The config file is sourced as bash, so `config set` accepts only known scalar keys; allowing an arbitrary key would let a value inject code into every later run, and hook functions are edited by hand.
