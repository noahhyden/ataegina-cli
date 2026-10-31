## A recorded pid needs its start-time checked before it is killed

The OS can recycle a pid recorded at `up` for an unrelated process before `down` runs, and killing it plus its tree takes out the innocent; compare the recorded `ps -o lstart=` token and skip on mismatch.
