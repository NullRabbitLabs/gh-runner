# gh-runner

Self-hosted GitHub Actions runner container with Docker-in-Docker, pre-loaded toolchains, and parallel scaling.

## Architecture

Each runner instance is a pair of containers: an ephemeral GitHub Actions runner and a DinD (Docker-in-Docker) sidecar. Runners register at the org level, execute one job, then exit and re-register — matching `ubuntu-latest` behavior.

```
┌─────────────────────────────────────────────────┐
│  Host                                           │
│                                                 │
│  ┌──────────────┐  ┌──────────────┐             │
│  │ ghrunner-1   │  │ ghrunner-2   │  ...N       │
│  │ ┌──────────┐ │  │ ┌──────────┐ │             │
│  │ │  runner   │ │  │ │  runner   │ │             │
│  │ │ (GH Acts) │ │  │ │ (GH Acts) │ │             │
│  │ └────┬─────┘ │  │ └────┬─────┘ │             │
│  │      │tcp    │  │      │tcp    │             │
│  │ ┌────▼─────┐ │  │ ┌────▼─────┐ │             │
│  │ │  dind    │ │  │ │  dind    │ │             │
│  │ │ (docker) │ │  │ │ (docker) │ │             │
│  │ └──────────┘ │  │ └──────────┘ │             │
│  └──────────────┘  └──────────────┘             │
│                                                 │
│  Shared volumes: cargo, go-mod, npm caches      │
│  Isolated volumes: dind-storage, _work per pair  │
└─────────────────────────────────────────────────┘
```

## Pre-installed toolchains

- **Rust** (stable) — with `x86_64-unknown-linux-musl` target, rustfmt, clippy
- **Go** 1.24
- **Node.js** 20
- **Python 3** + pip
- **Docker CLI** + Buildx + Compose
- **Packer**, **doctl**, **gh** CLI
- Build tools: build-essential, cmake, clang, llvm, pkg-config, libssl-dev, libelf-dev, musl-tools

## Quick start

```bash
# 1. Configure
cp .env.example .env
# Edit .env — set GITHUB_PAT (needs admin:org scope)

# 2. Launch two runners
./scale.sh up

# 3. Check status
./scale.sh status
```

Runners will appear in your GitHub org under **Settings → Actions → Runners**.

## Usage

```bash
./scale.sh up              # Start RUNNER_COUNT runner instances (default: 2)
./scale.sh down            # Stop all instances
./scale.sh status          # Show status of all instances
./scale.sh logs <N>        # Tail logs for instance N
./scale.sh restart         # Stop then start all instances
```

Set `RUNNER_COUNT` in `.env` or as an environment variable to control parallelism.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `GITHUB_ORG` | `NullRabbitLabs` | GitHub organization |
| `GITHUB_PAT` | — | Personal access token (requires `admin:org` scope) |
| `RUNNER_NAME` | Auto-set by scale.sh | Runner name prefix |
| `RUNNER_LABELS` | `self-hosted,linux,x64,nullrabbit` | Comma-separated labels |
| `RUNNER_GROUP` | `default` | Runner group |
| `RUNNER_COUNT` | `2` | Number of parallel runners |

## Workflow migration

Update `runs-on` in your workflow files:

```yaml
# Before
runs-on: ubuntu-latest

# After
runs-on: [self-hosted, linux, x64, nullrabbit]
```

## Design decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Docker access | DinD sidecar | Full isolation between parallel runners |
| Registration | Org-level | One config covers all repos |
| Runner mode | Ephemeral | Clean slate per job, matches `ubuntu-latest` behavior |
| Base image | Ubuntu 24.04 | Matches `ubuntu-latest` that workflows already target |
| Caching | Shared external volumes | Fast restarts without re-downloading deps |
