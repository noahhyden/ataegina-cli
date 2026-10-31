## config set passes the value via ENVIRON, never awk -v

awk -v mangles backslashes in the single-quoted value, so config set hands it over through ENVIRON and replaces only the first top-level KEY= line, leaving comments and local KEY= lines alone.
