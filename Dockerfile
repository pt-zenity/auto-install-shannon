# =============================================================================
# Dockerfile — Shannon-Ready Container Image
# =============================================================================
# Builds an Ubuntu 24.04 image with Shannon pre-installed and ready to run.
# Shannon requires Docker-in-Docker (DinD) for its worker containers.
#
# Build:
#   docker build -t shannon-ready .
#
# Run (DinD mode — required):
#   docker run -it --privileged \
#     -e SHANNON_AI_API_KEY=your-api-key \
#     -e SHANNON_AI_MODEL=anthropic:claude-sonnet-4-6 \
#     shannon-ready
#
# Run with Kagiro:
#   docker run -it --privileged \
#     -e SHANNON_AI_API_KEY=kagiro-your-key \
#     -e SHANNON_AI_MODEL=anthropic:claude-haiku-5-5 \
#     -e SHANNON_AI_BASE_URL=https://api.kagiro.net \
#     shannon-ready
#
# Mount a target repo for scanning:
#   docker run -it --privileged \
#     -e SHANNON_AI_API_KEY=your-api-key \
#     -v /path/to/target-repo:/home/shannon/target:ro \
#     shannon-ready \
#     ./shannon start -u https://target.com -r /home/shannon/target
#
# Alternative: mount host Docker socket (no --privileged needed):
#   docker run -it \
#     -v /var/run/docker.sock:/var/run/docker.sock \
#     -e SHANNON_AI_API_KEY=your-api-key \
#     shannon-ready
# =============================================================================

# --- Stage 1: Build ---
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    git \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Enable corepack and install pnpm 10.33.0 (matches Shannon's packageManager)
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate

# Clone Shannon
ARG SHANNON_BRANCH=main
RUN git clone --depth 1 -b ${SHANNON_BRANCH} \
    https://github.com/KeygraphHQ/shannon.git /build/shannon

WORKDIR /build/shannon

# Install dependencies and build
RUN pnpm install --frozen-lockfile && pnpm build

# Verify build artifacts exist
RUN test -f apps/cli/dist/index.mjs && test -f apps/worker/dist/temporal/worker.js

# --- Stage 2: Runtime ---
FROM ubuntu:24.04

LABEL maintainer="pt-zenity"
LABEL description="Shannon AI Pentester — pre-built and ready to run"
LABEL org.opencontainers.image.source="https://github.com/pt-zenity/auto-install-shannon"

ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    git \
    gnupg \
    lsb-release \
    sudo \
    iptables \
    && rm -rf /var/lib/apt/lists/*

# Switch iptables to legacy mode — nf_tables backend fails inside containers
# because the kernel nftables API requires privileges most container runtimes
# don't grant, even with --privileged on older kernels
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true \
    && update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true

# Install Docker CLI + Compose plugin (Shannon needs Docker to run worker containers)
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
       | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
       | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       docker-ce \
       docker-ce-cli \
       containerd.io \
       docker-buildx-plugin \
       docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Enable corepack and install pnpm
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate

# Create non-root user (Shannon refuses to run as root)
RUN useradd -m -s /bin/bash shannon \
    && usermod -aG docker shannon

# Copy built Shannon from builder stage
COPY --from=builder --chown=shannon:shannon /build/shannon /home/shannon/shannon

# Copy .env.example as template
RUN cp /home/shannon/shannon/.env.example /home/shannon/shannon/.env.template

# Copy entrypoint
COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Workspaces volume (scan results persist here)
VOLUME ["/home/shannon/shannon/workspaces"]

# Temporal ports
EXPOSE 7233 8233

WORKDIR /home/shannon/shannon

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["bash"]
