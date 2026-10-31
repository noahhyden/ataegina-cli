## down must reap the whole process tree, enumerated before any kill

Dev servers spawn workers that never hold the socket (uvicorn --reload, vite, next dev); kill only the holder and they orphan to init and leak every cycle, so snapshot descendants first, then SIGTERM, grace, SIGKILL.
