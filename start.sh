#!/usr/bin/env bash
set -euo pipefail

# ── Required env ─────────────────────────────────────────────────────
: "${GITHUB_PAT:?GITHUB_PAT must be set}"
: "${GITHUB_ORG:?GITHUB_ORG must be set}"

RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,linux,x64,nullrabbit}"
RUNNER_GROUP="${RUNNER_GROUP:-default}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-_work}"

# ── Mint a fresh registration token ─────────────────────────────────
echo "Requesting registration token for org: ${GITHUB_ORG}..."
REG_TOKEN=$(curl -sX POST \
  -H "Authorization: token ${GITHUB_PAT}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/orgs/${GITHUB_ORG}/actions/runners/registration-token" \
  | jq -r '.token')

if [ -z "${REG_TOKEN}" ] || [ "${REG_TOKEN}" = "null" ]; then
  echo "ERROR: Failed to obtain registration token. Check GITHUB_PAT permissions." >&2
  exit 1
fi

# ── Wait for DinD sidecar ────────────────────────────────────────────
if [ -n "${DOCKER_HOST:-}" ]; then
  echo "Waiting for Docker daemon at ${DOCKER_HOST}..."
  for i in $(seq 1 30); do
    if docker info >/dev/null 2>&1; then
      echo "Docker daemon is ready."
      break
    fi
    if [ "$i" -eq 30 ]; then
      echo "ERROR: Docker daemon not available after 30s." >&2
      exit 1
    fi
    sleep 1
  done
fi

# ── Cleanup function ────────────────────────────────────────────────
cleanup() {
  echo "Caught signal — removing runner..."
  REMOVE_TOKEN=$(curl -sX POST \
    -H "Authorization: token ${GITHUB_PAT}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/orgs/${GITHUB_ORG}/actions/runners/remove-token" \
    | jq -r '.token')
  ./config.sh remove --token "${REMOVE_TOKEN}" 2>/dev/null || true
  exit 0
}

trap cleanup SIGTERM SIGINT

# ── Configure runner ─────────────────────────────────────────────────
echo "Configuring runner: ${RUNNER_NAME}..."
./config.sh \
  --url "https://github.com/${GITHUB_ORG}" \
  --token "${REG_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "${RUNNER_LABELS}" \
  --runnergroup "${RUNNER_GROUP}" \
  --work "${RUNNER_WORKDIR}" \
  --ephemeral \
  --replace \
  --disableupdate \
  --unattended

# ── Run (background + wait for signal handling) ──────────────────────
echo "Starting runner..."
./run.sh &
wait $!

# ── Ephemeral mode: runner exits after one job — exit cleanly ────────
echo "Runner has finished (ephemeral). Exiting."
