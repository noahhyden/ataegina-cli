## lsof must pass -sTCP:LISTEN

Plain `lsof -ti tcp:PORT` also matches ESTABLISHED clients, so a browser on the dev server reads as the port holder and `down` refuses to reap ataegina's own server; keep -sTCP:LISTEN to match `ss -l`.
