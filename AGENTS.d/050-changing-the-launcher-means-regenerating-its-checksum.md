## Changing the launcher means regenerating its checksum

release-verify runs `shasum -a 256 -c ataegina.sha256`, so any commit touching ataegina must also run `shasum -a 256 ataegina > ataegina.sha256`; install.sh and `ataegina update` both verify a download against that published digest.
