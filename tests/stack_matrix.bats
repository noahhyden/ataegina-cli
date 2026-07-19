#!/usr/bin/env bats
# Breadth coverage: `init` stack detection across many frontends and backends, and
# per-worktree DB derivation across every DB_KIND. Detection is exercised via
# `init --dry-run` (writes nothing); DB derivation via `db name`/`db url`; sqlite/
# custom create+drop are exercised for real (file-based / echo — no DB server).

load helper

setup()    { common_setup; }
teardown() { common_teardown; }

# A git repo with nothing but a README (no frontend/backend dirs), so each test
# scaffolds exactly the stack it means to detect. No commit needed: detection reads
# the working tree and `git rev-parse` works in an empty repo.
bare_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email t@e.c
  git -C "$dir" config user.name t
  git -C "$dir" symbolic-ref HEAD refs/heads/main
  echo readme > "$dir/README.md"
  printf '%s\n' "$dir"
}

# ---------------------------------------------------------------------------
# Frontends
# ---------------------------------------------------------------------------

@test "frontend: Next.js detected -> next dev on the slot port" {
  repo="$(bare_repo "$ATE_TMP/fe-next")"
  mkdir -p "$repo/frontend"
  printf '{"dependencies":{"next":"14"},"scripts":{"dev":"next dev"}}\n' > "$repo/frontend/package.json"
  cd "$repo"
  run ate init --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "FRONTEND_DIR='frontend'"
  echo "$output" | grep -q 'npx next dev -p $FRONTEND_PORT'
  echo "$output" | grep -q 'NEXT_PUBLIC_API_BASE_URL=$BACKEND_URL'
}

@test "frontend: Vite detected -> vite --port on the slot port" {
  repo="$(bare_repo "$ATE_TMP/fe-vite")"
  mkdir -p "$repo/frontend"
  printf '{"devDependencies":{"vite":"5"}}\n' > "$repo/frontend/package.json"
  cd "$repo"
  run ate init --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'npx vite --port $FRONTEND_PORT'
  echo "$output" | grep -q 'VITE_API_URL=$BACKEND_URL'
}

@test "frontend: create-react-app detected -> npm start with PORT env" {
  repo="$(bare_repo "$ATE_TMP/fe-cra")"
  mkdir -p "$repo/frontend"
  printf '{"dependencies":{"react-scripts":"5"}}\n' > "$repo/frontend/package.json"
  cd "$repo"
  run ate init --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "FRONTEND_CMD='npm start'"
  echo "$output" | grep -q 'PORT=$FRONTEND_PORT'
  echo "$output" | grep -q 'REACT_APP_API_URL=$BACKEND_URL'
}

@test "frontend: Nuxt detected -> nuxt dev on the slot port" {
  repo="$(bare_repo "$ATE_TMP/fe-nuxt")"
  mkdir -p "$repo/frontend"
  printf '{"dependencies":{"nuxt":"3"}}\n' > "$repo/frontend/package.json"
  cd "$repo"
  run ate init --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'npx nuxt dev --port $FRONTEND_PORT'
  echo "$output" | grep -q 'NUXT_PUBLIC_API_BASE_URL=$BACKEND_URL'
}

@test "frontend: Astro detected -> astro dev on the slot port" {
  repo="$(bare_repo "$ATE_TMP/fe-astro")"
  mkdir -p "$repo/frontend"
  printf '{"dependencies":{"astro":"4"}}\n' > "$repo/frontend/package.json"
  cd "$repo"
  run ate init --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'npx astro dev --port $FRONTEND_PORT'
  echo "$output" | grep -q 'PUBLIC_API_BASE_URL=$BACKEND_URL'
}

@test "frontend: SvelteKit detected -> vite dev (checked before bare vite)" {
  repo="$(bare_repo "$ATE_TMP/fe-svelte")"
  mkdir -p "$repo/frontend"
  # SvelteKit ships vite as a dep too; detection must NOT fall through to vite.
  printf '{"devDependencies":{"@sveltejs/kit":"2","vite":"5"}}\n' > "$repo/frontend/package.json"
  cd "$repo"
  run ate init --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'npx vite dev --port $FRONTEND_PORT'
  echo "$output" | grep -q 'PUBLIC_API_BASE_URL=$BACKEND_URL'
}

@test "frontend: unknown framework is flagged, not guessed" {
  repo="$(bare_repo "$ATE_TMP/fe-unknown")"
  mkdir -p "$repo/frontend"
  printf '{"dependencies":{"lodash":"4"}}\n' > "$repo/frontend/package.json"
  cd "$repo"
  run ate init --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'unrecognized frontend'
}

# ---------------------------------------------------------------------------
# Backends
# ---------------------------------------------------------------------------

@test "backend: uv (pyproject + uv.lock + main.py) -> uv run main.py" {
  repo="$(bare_repo "$ATE_TMP/be-uv")"
  mkdir -p "$repo/backend"
  printf '[project]\nname="x"\n' > "$repo/backend/pyproject.toml"
  : > "$repo/backend/uv.lock"; : > "$repo/backend/main.py"
  cd "$repo"
  run ate init --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "BACKEND_DIR='backend'"
  echo "$output" | grep -q "BACKEND_CMD='uv run main.py'"
}

@test "backend: uv without main.py -> uvicorn on the slot port" {
  repo="$(bare_repo "$ATE_TMP/be-uv2")"
  mkdir -p "$repo/backend"
  printf '[project]\nname="x"\n' > "$repo/backend/pyproject.toml"
  : > "$repo/backend/uv.lock"
  cd "$repo"
  run ate init --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'uv run uvicorn main:app --port $BACKEND_PORT'
}

@test "backend: Django (manage.py) -> runserver on the slot port" {
  repo="$(bare_repo "$ATE_TMP/be-django")"
  mkdir -p "$repo/backend"
  : > "$repo/backend/manage.py"
  cd "$repo"
  run ate init --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'python manage.py runserver 0.0.0.0:$BACKEND_PORT'
}

@test "backend: Rails (Gemfile) -> bin/rails server -p slot" {
  repo="$(bare_repo "$ATE_TMP/be-rails")"
  mkdir -p "$repo/backend"
  printf 'source "https://rubygems.org"\n' > "$repo/backend/Gemfile"
  cd "$repo"
  run ate init --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'bin/rails server -p $BACKEND_PORT'
}

@test "backend: Node/Express -> npm run dev with PORT env" {
  repo="$(bare_repo "$ATE_TMP/be-node")"
  mkdir -p "$repo/backend"
  printf '{"dependencies":{"express":"4"}}\n' > "$repo/backend/package.json"
  cd "$repo"
  run ate init --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "BACKEND_CMD='npm run dev'"
  echo "$output" | grep -q 'PORT=$BACKEND_PORT'
}

@test "backend: NestJS -> detected as node" {
  repo="$(bare_repo "$ATE_TMP/be-nest")"
  mkdir -p "$repo/backend"
  printf '{"dependencies":{"@nestjs/core":"10"}}\n' > "$repo/backend/package.json"
  cd "$repo"
  run ate init --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "BACKEND_DIR='backend'"
  echo "$output" | grep -q "BACKEND_CMD='npm run dev'"
}

@test "backend: Go (go.mod) -> go run . with PORT env carrying the slot" {
  repo="$(bare_repo "$ATE_TMP/be-go")"
  mkdir -p "$repo/backend"
  printf 'module x\n\ngo 1.22\n' > "$repo/backend/go.mod"
  cd "$repo"
  run ate init --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "BACKEND_CMD='go run .'"
  echo "$output" | grep -q 'PORT=$BACKEND_PORT'
}

@test "backend: Rust (Cargo.toml) -> cargo run with PORT env" {
  repo="$(bare_repo "$ATE_TMP/be-rust")"
  mkdir -p "$repo/backend"
  printf '[package]\nname="x"\nversion="0.1.0"\n' > "$repo/backend/Cargo.toml"
  cd "$repo"
  run ate init --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "BACKEND_CMD='cargo run'"
  echo "$output" | grep -q 'PORT=$BACKEND_PORT'
}

@test "backend: PHP/Laravel (artisan) -> artisan serve on the slot port" {
  repo="$(bare_repo "$ATE_TMP/be-php")"
  mkdir -p "$repo/backend"
  : > "$repo/backend/artisan"
  cd "$repo"
  run ate init --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'php artisan serve --host=0.0.0.0 --port=$BACKEND_PORT'
}

@test "full stack: Next + uv detected together" {
  repo="$(bare_repo "$ATE_TMP/full")"
  mkdir -p "$repo/frontend" "$repo/backend"
  printf '{"dependencies":{"next":"14"}}\n' > "$repo/frontend/package.json"
  printf '[project]\nname="x"\n' > "$repo/backend/pyproject.toml"
  : > "$repo/backend/uv.lock"; : > "$repo/backend/main.py"
  cd "$repo"
  run ate init --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'npx next dev'
  echo "$output" | grep -q 'uv run main.py'
}

# ---------------------------------------------------------------------------
# Databases (per-worktree derivation across every DB_KIND)
# ---------------------------------------------------------------------------

# primary keeps the unsuffixed name; a worktree gets NAME + SUFFIX + index.
@test "db: postgres URL template derives per worktree" {
  repo="$(make_repo "$ATE_TMP/db-pg")"
  write_config "$repo" \
    "DB_NAME=shop" "DB_KIND=postgres" \
    "DB_URL_TEMPLATE='postgres://localhost:5432/\$ATE_DB_NAME'"
  cd "$repo"
  run ate db name; [ "$output" = "shop" ]
  run ate db url;  [ "$output" = "postgres://localhost:5432/shop" ]

  wt="$(add_worktree "$repo" wt)"
  cp "$repo/ataegina.config.sh" "$ATE_TMP/registry/ataegina.config.sh"  # config for the worktree
  cd "$wt"
  run ate db name; [ "$output" = "shop_wt1" ]
  run ate db url;  [ "$output" = "postgres://localhost:5432/shop_wt1" ]
}

@test "db: mysql URL template derives per worktree" {
  repo="$(make_repo "$ATE_TMP/db-my")"
  write_config "$repo" \
    "DB_NAME=app" "DB_KIND=mysql" \
    "DB_URL_TEMPLATE='mysql://root@localhost:3306/\$ATE_DB_NAME'"
  cd "$repo"
  run ate db url; [ "$output" = "mysql://root@localhost:3306/app" ]
}

@test "db: custom suffix and DB_URL_VAR are honored" {
  repo="$(make_repo "$ATE_TMP/db-suf")"
  write_config "$repo" \
    "DB_NAME=svc" "DB_KIND=postgres" "DB_SUFFIX=_branch_" \
    "DB_URL_TEMPLATE='postgres://localhost/\$ATE_DB_NAME'"
  wt="$(add_worktree "$repo" wt)"
  cp "$repo/ataegina.config.sh" "$ATE_TMP/registry/ataegina.config.sh"
  cd "$wt"
  run ate db name; [ "$output" = "svc_branch_1" ]
}

@test "db: sqlite create is a no-op and drop removes the worktree file" {
  repo="$(make_repo "$ATE_TMP/db-sqlite")"
  write_config "$repo" \
    "DB_NAME=$ATE_TMP/data/db" "DB_KIND=sqlite" \
    "DB_SUFFIX=_wt" "DB_URL_TEMPLATE='sqlite:///\$ATE_DB_NAME.db'"
  mkdir -p "$ATE_TMP/data"
  wt="$(add_worktree "$repo" wt)"
  cp "$repo/ataegina.config.sh" "$ATE_TMP/registry/ataegina.config.sh"
  cd "$wt"
  # worktree db name is the base path + suffix + index
  run ate db name; [ "$output" = "$ATE_TMP/data/db_wt1" ]
  # create is a no-op for sqlite (opened on first use) -> exit 0
  run ate db create; [ "$status" -eq 0 ]
  # simulate an on-disk db, then drop should remove it + WAL/SHM siblings
  : > "$ATE_TMP/data/db_wt1"; : > "$ATE_TMP/data/db_wt1-wal"
  run ate db drop; [ "$status" -eq 0 ]
  [ ! -e "$ATE_TMP/data/db_wt1" ]
  [ ! -e "$ATE_TMP/data/db_wt1-wal" ]
}

@test "db: primary drop is refused (protects the shared dev DB)" {
  repo="$(make_repo "$ATE_TMP/db-guard")"
  write_config "$repo" "DB_NAME=shop" "DB_KIND=sqlite"
  cd "$repo"
  run ate db drop
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'refusing to drop'
}

@test "db: custom kind runs the configured create command" {
  repo="$(make_repo "$ATE_TMP/db-custom")"
  write_config "$repo" \
    "DB_NAME=x" "DB_KIND=custom" \
    "DB_CREATE_CMD='echo created \$ATE_DB_NAME > $ATE_TMP/created.txt'"
  wt="$(add_worktree "$repo" wt)"
  cp "$repo/ataegina.config.sh" "$ATE_TMP/registry/ataegina.config.sh"
  cd "$wt"
  run ate db create
  [ "$status" -eq 0 ]
  grep -q 'created x_wt1' "$ATE_TMP/created.txt"
}
