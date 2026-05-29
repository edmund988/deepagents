#!/usr/bin/env bash
set -euo pipefail

checks_run=0

has_npm_script() {
  local script="$1"
  node -e "const pkg = require('./package.json'); process.exit(pkg.scripts && pkg.scripts[process.argv[1]] ? 0 : 1)" "$script" >/dev/null 2>&1
}

run_npm_script() {
  local script="$1"
  has_npm_script "$script" || return 0
  npm run "$script"
  checks_run=$((checks_run + 1))
}

if [ -f package.json ]; then
  if command -v corepack >/dev/null 2>&1; then
    corepack enable || true
  fi

  if [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then
    pnpm install --frozen-lockfile
  elif [ -f yarn.lock ] && command -v yarn >/dev/null 2>&1; then
    yarn install --immutable || yarn install --frozen-lockfile
  elif [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
    npm ci
  else
    npm install
  fi

  run_npm_script lint
  run_npm_script typecheck
  run_npm_script test
  run_npm_script docs:check
fi

if [ -f Makefile ]; then
  for target in lint test docs-check; do
    if grep -Eq "^${target}:" Makefile; then
      make "$target"
      checks_run=$((checks_run + 1))
    fi
  done
fi

if [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -d tests ]; then
  python3 -m pip install --upgrade pip

  if [ -f requirements.txt ]; then
    python3 -m pip install -r requirements.txt
  fi

  if [ -f pyproject.toml ]; then
    python3 -m pip install -e ".[dev]" || python3 -m pip install -e . || true
  fi

  if python3 -m pytest --version >/dev/null 2>&1; then
    python3 -m pytest
    checks_run=$((checks_run + 1))
  fi
fi

if [ "$checks_run" -eq 0 ]; then
  echo "::warning title=No project validation found::No supported lint, test, typecheck, docs, Makefile, or pytest checks were found."
fi
