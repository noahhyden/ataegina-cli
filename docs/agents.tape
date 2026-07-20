# VHS tape for the ataegina agent-native demo (JSON + readiness gating).
# Regenerate with:  bash docs/demo-setup.sh && vhs docs/agents.tape
# demo-setup.sh builds a throwaway full-stack repo under /tmp/ataegina-demo.
# The dev commands are swapped for tiny stand-in servers so `up` actually
# binds the slot's ports without an npm install.

Output docs/agents.gif

Set Shell "bash"
Set FontSize 16
Set Width 1200
Set Height 800
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 35ms

# --- hidden setup: PATH, registry, config, a second registered worktree ---
Hide
Type "export PATH=/tmp/ataegina-demo/bin:$PATH" Enter
Type "export ATE_REGISTRY_DIR=/tmp/ataegina-demo/.reg PS1='$ '" Enter
Type "cd /tmp/ataegina-demo/app && ataegina init --yes >/dev/null 2>&1" Enter
Type "ataegina config set FRONT_PORT_BASE 3000 >/dev/null" Enter
Type "ataegina config set BACK_PORT_BASE 8000 >/dev/null" Enter
Type "ataegina config set DB_NAME appdb >/dev/null" Enter
Type "ataegina config set DB_KIND postgres >/dev/null" Enter
Type "ataegina config set FRONTEND_CMD 'python3 -m http.server $FRONTEND_PORT' >/dev/null" Enter
Type "ataegina config set BACKEND_CMD 'python3 -m http.server $BACKEND_PORT' >/dev/null" Enter
Type "git worktree add ../app-feature -b feature >/dev/null 2>&1" Enter
Type "( cd ../app-feature && ataegina ports >/dev/null )" Enter
Type "clear" Enter
Show

Sleep 700ms
# One call per agent: claim the slot, BLOCK until the servers actually answer,
# and emit a machine-readable slot object. Exit 0 is the readiness gate.
Type "ataegina up --wait --json > slot.json && echo '# ready -> agent can proceed'" Enter
Sleep 4s

# That JSON is what the agent parses — note ready.backend / ready.frontend:
Type "python3 -m json.tool slot.json" Enter
Sleep 3.5s
Type "clear" Sleep 300ms Enter

# The whole fleet in one array — each worktree's ports, db, and live state:
Type "ataegina list --json | python3 -m json.tool" Enter
Sleep 4s

# Clean shutdown.
Type "ataegina down" Enter
Sleep 2.5s
