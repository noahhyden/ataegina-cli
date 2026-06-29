#!/usr/bin/env bats
# init: stack detection. `ataegina init --dry-run` prints the config it WOULD
# generate and writes nothing. Regression coverage for a silent crash (exit 1,
# no output) on a package.json that has no "dev" script, where pkg_dev_script's
# grep|head|sed pipeline failed under `set -o pipefail` and aborted init.

load helper

setup() { common_setup; }
teardown() { common_teardown; }

# A git repo with a single root package.json, echoing its path.
make_pkg_repo() {
  local dir="$1" pkg="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "ate test"
  git -C "$dir" symbolic-ref HEAD refs/heads/main
  printf '%s\n' "$pkg" > "$dir/package.json"
  printf 'ataegina.config.sh\n' > "$dir/.gitignore"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m init
  printf '%s\n' "$dir"
}

@test "init --dry-run does not crash on a package.json with no dev script" {
  repo="$(make_pkg_repo "$ATE_TMP/clilib" '{ "name": "clilib", "bin": { "x": "bin/x" }, "dependencies": { "chalk": "5" } }')"
  cd "$repo"
  run ate init --dry-run
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ ! -f "$repo/ataegina.config.sh" ]
}

@test "init --dry-run detects a Next.js frontend" {
  repo="$(make_pkg_repo "$ATE_TMP/web" '{ "name":"web","scripts":{"dev":"next dev"},"dependencies":{"next":"14.0.0"} }')"
  cd "$repo"
  run ate init --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "frontend: next"
}

@test "init --dry-run detects a uv backend with main.py" {
  repo="$ATE_TMP/svc"; mkdir -p "$repo/backend"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "ate test"
  git -C "$repo" symbolic-ref HEAD refs/heads/main
  printf '[project]\nname = "svc"\n' > "$repo/backend/pyproject.toml"
  : > "$repo/backend/uv.lock"
  echo "print('hi')" > "$repo/backend/main.py"
  printf 'ataegina.config.sh\n' > "$repo/.gitignore"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "init"
  cd "$repo"
  run ate init --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "uv run main.py"
}

@test "init --dry-run on a minimal package.json still writes nothing" {
  repo="$(make_pkg_repo "$ATE_TMP/none" '{ "name":"none" }')"
  cd "$repo"
  run ate init --dry-run
  [ "$status" -eq 0 ]
  [ ! -f "$repo/ataegina.config.sh" ]
}
