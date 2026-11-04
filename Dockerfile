# =============================================================================
# Dockerfile — Shannon-Ready Container Image
# =============================================================================
# Builds an Ubuntu 24.04 image with Shannon pre-installed and ready to run.
# Shannon needs Docker for worker containers — this image uses the HOST's
# Docker daemon via socket mount (no --privileged needed).
#
# Build:
#   docker build -t shannon-ready .
#
# Run (mount host Docker socket):
#   docker run -it \
#     -v /var/run/docker.sock:/var/run/docker.sock \
#     -e SHANNON_AI_API_KEY=your-api-key \
#     -e SHANNON_AI_MODEL=anthropic:claude-sonnet-4-6 \
#     shannon-ready
#
# Run with Kagiro:
#   docker run -it \
#     -v /var/run/docker.sock:/var/run/docker.sock \
#     -e SHANNON_AI_API_KEY=kagiro-your-key \
#     -e SHANNON_AI_MODEL=anthropic:claude-haiku-5-5 \
#     -e SHANNON_AI_BASE_URL=https://api.kagiro.net \
#     shannon-ready
#
# Mount a target repo for scanning:
#   docker run -it \
#     -v /var/run/docker.sock:/var/run/docker.sock \
#     -e SHANNON_AI_API_KEY=your-api-key \
#     -v /path/to/target-repo:/home/shannon/target:ro \
#     shannon-ready \
#     ./shannon start -u https://target.com -r /home/shannon/target
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
LABEL description="Shannon AI Pentester — pre-built, uses host Docker via socket mount"
LABEL org.opencontainers.image.source="https://github.com/pt-zenity/auto-install-shannon"

ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies + Docker CLI only (no daemon — uses host Docker)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    git \
    gnupg \
    lsb-release \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI + Compose plugin ONLY (no docker-ce / containerd)
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
       | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
       | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       docker-ce-cli \
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
RUN useradd -m -s /bin/bash shannon

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
