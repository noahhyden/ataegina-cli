## Default hooks are defined before the config is sourced

A user redefining ate_start_*, ate_stop_* or ate_db_* in the config overrides the default only because the defaults are defined first; moving the config load above them silently breaks that escape hatch.
