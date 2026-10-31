## Under --json, swap fds so stdout stays pure JSON

doctor, up and restart save the real stdout on fd 3 (restart uses fd 4 for its stop phase) and route everything else to stderr, restoring it only to emit the object; any stray stdout line breaks agent parsing.
