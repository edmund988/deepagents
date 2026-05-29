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

ensure_python_tools() {
  if [ -n "${GATEKEEPER_PYTHON_TOOLS_READY:-}" ]; then
    return
  fi

  local venv_dir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/gatekeeper-python-tools"
  python3 -m venv "$venv_dir"
  # shellcheck disable=SC1091
  . "$venv_dir/bin/activate"
  python3 -m pip install --upgrade pip
  GATEKEEPER_PYTHON_TOOLS_READY=1
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
  if [ -f uv.lock ]; then
    if ! command -v uv >/dev/null 2>&1; then
      ensure_python_tools
      python3 -m pip install uv
    fi
    uv sync --locked --dev

    if [ -d tests ]; then
      uv run pytest
      checks_run=$((checks_run + 1))
    fi

    if [ -f pyproject.toml ] && grep -Eq '^\[tool\.ruff' pyproject.toml; then
      uv run ruff check
      checks_run=$((checks_run + 1))
    fi
  else
    ensure_python_tools

    if [ -f requirements.txt ]; then
      python3 -m pip install -r requirements.txt
    fi

    if [ -f pyproject.toml ]; then
      python3 -m pip install -e .
    fi

    if [ -d tests ]; then
      python3 -m pip install pytest
      python3 -m pytest
      checks_run=$((checks_run + 1))
    fi

    if [ -f pyproject.toml ] && grep -Eq '^\[tool\.ruff' pyproject.toml; then
      python3 -m pip install ruff
      python3 -m ruff check
      checks_run=$((checks_run + 1))
    fi
  fi
fi

if [ "$checks_run" -eq 0 ]; then
  echo "::warning title=No project validation found::No supported lint, test, typecheck, docs, Makefile, or pytest checks were found."
fi
