# ── Stage 1: base ────────────────────────────────────────────────────
FROM ubuntu:24.04 AS base

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake pkg-config libssl-dev \
    clang llvm libelf-dev musl-tools \
    git curl jq openssh-client unzip tar \
    ca-certificates sudo gnupg iptables \
    software-properties-common lsb-release \
    zlib1g-dev libffi-dev \
  && rm -rf /var/lib/apt/lists/*

# ── Stage 2: toolchain ──────────────────────────────────────────────
FROM base AS toolchain

# ── Rust (stable) ────────────────────────────────────────────────────
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH="/usr/local/cargo/bin:${PATH}"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain stable --profile minimal \
  && rustup target add x86_64-unknown-linux-musl \
  && rustup component add rustfmt clippy \
  && chmod -R a+rw "${RUSTUP_HOME}" "${CARGO_HOME}"

# ── Go 1.24 ──────────────────────────────────────────────────────────
ARG GO_VERSION=1.24.13
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
    | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:${PATH}" \
    GOPATH="/home/runner/go" \
    GOMODCACHE="/home/runner/go/pkg/mod"

# ── Node.js 20 ───────────────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

# ── Python 3 + pip ───────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
  && rm -rf /var/lib/apt/lists/*

# ── Docker CLI + Buildx + Compose ────────────────────────────────────
RUN install -m 0755 -d /etc/apt/keyrings \
  && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
     | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
  && chmod a+r /etc/apt/keyrings/docker.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
     https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
     > /etc/apt/sources.list.d/docker.list \
  && apt-get update && apt-get install -y --no-install-recommends \
     docker-ce-cli docker-buildx-plugin docker-compose-plugin \
  && rm -rf /var/lib/apt/lists/*

# ── Packer ───────────────────────────────────────────────────────────
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg \
  && echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] \
     https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
     > /etc/apt/sources.list.d/hashicorp.list \
  && apt-get update && apt-get install -y --no-install-recommends packer \
  && rm -rf /var/lib/apt/lists/*

# ── doctl ────────────────────────────────────────────────────────────
ARG DOCTL_VERSION=1.151.0
RUN curl -fsSL "https://github.com/digitalocean/doctl/releases/download/v${DOCTL_VERSION}/doctl-${DOCTL_VERSION}-linux-amd64.tar.gz" \
    | tar -C /usr/local/bin -xz

# ── gh CLI ───────────────────────────────────────────────────────────
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
     | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
     https://cli.github.com/packages stable main" \
     > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y --no-install-recommends gh \
  && rm -rf /var/lib/apt/lists/*

# ── Stage 3: runner ─────────────────────────────────────────────────
FROM toolchain AS runner

ARG RUNNER_VERSION=2.332.0
ARG RUNNER_SHA256=f2094522a6b9afeab07ffb586d1eb3f190b6457074282796c497ce7dce9e0f2a

# Create non-root runner user with passwordless sudo
RUN useradd -m -u 1000 -s /bin/bash runner \
  && echo "runner ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner \
  && chmod 0440 /etc/sudoers.d/runner

WORKDIR /home/runner

# Download and verify GitHub Actions runner
RUN curl -fsSL -o runner.tar.gz \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
  && echo "${RUNNER_SHA256}  runner.tar.gz" | sha256sum -c - \
  && tar xzf runner.tar.gz \
  && rm runner.tar.gz \
  && ./bin/installdependencies.sh \
  && rm -rf /var/lib/apt/lists/*

# Fix ownership so runner user can operate
RUN chown -R runner:runner /home/runner

COPY --chmod=755 start.sh /home/runner/start.sh

USER runner

ENTRYPOINT ["/home/runner/start.sh"]
