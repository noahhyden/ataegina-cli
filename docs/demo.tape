# VHS tape for the ataegina README demo.
# Regenerate with:  vhs docs/demo.tape   (see docs/README of generation in PR)
# Setup expected beforehand: a sample full-stack git repo at /tmp/code/app
# (frontend/ = next, backend/ = express) and an empty registry at /tmp/code/.reg.

Output docs/demo.gif

Set Shell "bash"
Set FontSize 18
Set Width 1180
Set Height 600
Set Padding 26
Set Theme "Catppuccin Mocha"
Set TypingSpeed 40ms

# --- hidden setup: PATH, isolated registry, clean prompt ---
Hide
Type "export PATH=/Users/s01/repos/ataegina-cli:$PATH" Enter
Type "export ATE_REGISTRY_DIR=/tmp/code/.reg ATE_PORT_TOOL=none PS1='$ '" Enter
Type "cd /tmp/code/app && clear" Enter
Show

Sleep 800ms
Type "ataegina --version" Enter
Sleep 1.2s

# Detect the stack and write the config (one time, in the primary checkout).
Type "ataegina init --yes" Enter
Sleep 2s

# The primary checkout is index 0 -> the default ports.
Type "ataegina ports" Enter
Sleep 2.2s

# Spin up a second worktree for a feature branch...
Type "git worktree add ../app-feature -b feature" Enter
Sleep 1.6s
Type "cd ../app-feature" Enter
Sleep 600ms

# ...and it automatically gets the next free, collision-free slot.
Type "ataegina ports" Enter
Sleep 2.6s

# Every registered worktree, at a glance.
Type "cd ../app && ataegina list" Enter
Sleep 3s
