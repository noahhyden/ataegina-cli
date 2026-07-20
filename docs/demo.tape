# VHS tape for the ataegina README hero demo.
# Regenerate with:  bash docs/demo-setup.sh && vhs docs/demo.tape
# demo-setup.sh builds a throwaway full-stack repo (frontend/ = Next.js,
# backend/ = Express) under /tmp/ataegina-demo and installs the launcher there,
# so this tape is reproducible on any machine.

Output docs/demo.gif

Set Shell "bash"
Set FontSize 18
Set Width 1180
Set Height 640
Set Padding 26
Set Theme "Catppuccin Mocha"
Set TypingSpeed 40ms

# --- hidden setup: PATH, isolated registry, clean prompt ---
Hide
Type "export PATH=/tmp/ataegina-demo/bin:$PATH" Enter
Type "export ATE_REGISTRY_DIR=/tmp/ataegina-demo/.reg PS1='$ '" Enter
Type "cd /tmp/ataegina-demo/app && clear" Enter
Show

Sleep 800ms
Type "ataegina --version" Enter
Sleep 1.2s

# Detect the stack and write the config (one time, in the primary checkout).
Type "ataegina init --yes" Enter
Sleep 2s

# Turn on per-worktree databases for the demo (ports use the documented defaults).
Hide
Type "ataegina config set DB_NAME appdb >/dev/null" Enter
Type "ataegina config set DB_KIND postgres >/dev/null && clear" Enter
Show

# The primary checkout is index 0 -> the default ports and shared DB.
Type "ataegina ports" Enter
Sleep 2.4s

# Spin up a second worktree for a feature branch...
Type "git worktree add ../app-feature -b feature" Enter
Sleep 1.6s
Type "cd ../app-feature" Enter
Sleep 600ms

# ...and it automatically gets the next free, collision-free slot.
Type "ataegina ports" Enter
Sleep 2.6s

# Ports AND a database of its own — parallel work never shares schema or data.
Type "ataegina db name" Enter
Sleep 2.4s

# Every registered worktree, at a glance.
Type "cd ../app && ataegina list" Enter
Sleep 3.2s
