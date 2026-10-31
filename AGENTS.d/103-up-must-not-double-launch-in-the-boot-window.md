## up must not double-launch inside the boot window

Before the port binds, a second `up` guarding only on the port starts a second server and overwrites the pidfile so `down` can no longer reap the first; _ate_launch_in_progress guards it, and a dead or recycled pid allows a restart.
