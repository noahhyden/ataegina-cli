#!/usr/bin/env bash
# Build the throwaway sample repo the README demo tapes record against.
# Creates a full-stack git repo (frontend/ = Next.js, backend/ = Express) plus
# an empty registry, so `vhs docs/demo.tape` / `vhs docs/agents.tape` are
# reproducible on any machine. Everything lives under $DEMO_ROOT (default
# /tmp/ataegina-demo); re-running wipes and rebuilds it.
set -euo pipefail

DEMO_ROOT="${DEMO_ROOT:-/tmp/ataegina-demo}"
APP="$DEMO_ROOT/app"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

rm -rf "$DEMO_ROOT"
mkdir -p "$APP/frontend" "$APP/backend" "$DEMO_ROOT/.reg" "$DEMO_ROOT/bin"

# Install this repo's launcher at a fixed path so the tapes can put it on PATH
# without hardcoding a machine-specific location.
cp "$REPO/ataegina" "$DEMO_ROOT/bin/ataegina"
chmod +x "$DEMO_ROOT/bin/ataegina"

# --- frontend: a Next.js app (detected via the `next` dependency) ---
cat > "$APP/frontend/package.json" <<'JSON'
{
  "name": "web",
  "private": true,
  "scripts": { "dev": "next dev" },
  "dependencies": { "next": "^15.0.0", "react": "^19.0.0", "react-dom": "^19.0.0" }
}
JSON

# --- backend: an Express API (detected via the `express` dependency) ---
cat > "$APP/backend/package.json" <<'JSON'
{
  "name": "api",
  "private": true,
  "scripts": { "dev": "node server.js" },
  "dependencies": { "express": "^4.19.0" }
}
JSON

cd "$APP"
git init -q
git config user.email demo@example.com
git config user.name "ataegina demo"
git add -A
git commit -qm "sample full-stack app (Next.js + Express)"

echo "sample repo ready at $APP (registry: $DEMO_ROOT/.reg)"
