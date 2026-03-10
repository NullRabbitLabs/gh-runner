#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER_COUNT="${RUNNER_COUNT:-2}"

# Source .env if present
if [ -f "${SCRIPT_DIR}/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/.env"
  set +a
fi

SHARED_VOLUMES=(
  shared-cargo-registry
  shared-cargo-git
  shared-go-mod
  shared-go-build
  shared-npm-cache
)

ensure_shared_volumes() {
  for vol in "${SHARED_VOLUMES[@]}"; do
    if ! docker volume inspect "$vol" >/dev/null 2>&1; then
      echo "Creating shared volume: $vol"
      docker volume create "$vol"
    fi
  done
}

cmd_up() {
  ensure_shared_volumes
  echo "Starting ${RUNNER_COUNT} runner(s)..."
  for i in $(seq 1 "${RUNNER_COUNT}"); do
    echo "── Launching ghrunner-${i} ──"
    COMPOSE_PROJECT_NAME="ghrunner-${i}" \
    RUNNER_NAME="${GITHUB_ORG:-NullRabbitLabs}-runner-${i}" \
      docker compose -f "${SCRIPT_DIR}/docker-compose.yml" up -d --build
  done
  echo ""
  echo "All ${RUNNER_COUNT} runner(s) started."
  cmd_status
}

cmd_down() {
  echo "Stopping all runners..."
  for i in $(seq 1 "${RUNNER_COUNT}"); do
    echo "── Stopping ghrunner-${i} ──"
    COMPOSE_PROJECT_NAME="ghrunner-${i}" \
      docker compose -f "${SCRIPT_DIR}/docker-compose.yml" down || true
  done
  echo "All runners stopped."
}

cmd_status() {
  echo ""
  echo "Runner status:"
  echo "─────────────────────────────────────────"
  for i in $(seq 1 "${RUNNER_COUNT}"); do
    echo "── ghrunner-${i} ──"
    COMPOSE_PROJECT_NAME="ghrunner-${i}" \
      docker compose -f "${SCRIPT_DIR}/docker-compose.yml" ps 2>/dev/null || echo "  (not running)"
    echo ""
  done
}

cmd_logs() {
  local instance="${1:-}"
  if [ -z "$instance" ]; then
    echo "Usage: $0 logs <instance-number>"
    exit 1
  fi
  COMPOSE_PROJECT_NAME="ghrunner-${instance}" \
    docker compose -f "${SCRIPT_DIR}/docker-compose.yml" logs -f
}

cmd_restart() {
  cmd_down
  cmd_up
}

# ── Main ─────────────────────────────────────────────────────────────
case "${1:-help}" in
  up)      cmd_up ;;
  down)    cmd_down ;;
  status)  cmd_status ;;
  logs)    cmd_logs "${2:-}" ;;
  restart) cmd_restart ;;
  *)
    echo "Usage: $0 {up|down|status|logs <N>|restart}"
    echo ""
    echo "Environment variables:"
    echo "  RUNNER_COUNT   Number of parallel runners (default: 2)"
    echo "  GITHUB_ORG     GitHub organization name"
    echo "  GITHUB_PAT     GitHub Personal Access Token"
    exit 1
    ;;
esac
