#!/usr/bin/env bash
# =============================================================================
# docker-entrypoint.sh — Shannon container entrypoint
# =============================================================================
# Uses the HOST's Docker daemon via mounted socket (/var/run/docker.sock).
# No Docker-in-Docker — no --privileged needed.
# =============================================================================

set -euo pipefail

ENV_FILE="/home/shannon/shannon/.env"
SHANNON_HOME="/home/shannon/shannon"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; }
info() { echo -e "${CYAN}[i]${NC} $*"; }

# --- 1. Setup Docker socket access ---
setup_docker() {
    local socket="/var/run/docker.sock"

    if [[ ! -S "$socket" ]]; then
        err "Docker socket tidak ditemukan di ${socket}"
        echo ""
        err "ServerKit: mount Docker socket di container settings:"
        err "  Volume: /var/run/docker.sock:/var/run/docker.sock"
        echo ""
        err "Manual docker run:"
        err "  docker run -it -v /var/run/docker.sock:/var/run/docker.sock shannon-ready"
        exit 1
    fi

    # Grant shannon user access to the Docker socket
    # Match the socket's group inside the container
    local sock_gid
    sock_gid=$(stat -c '%g' "$socket")

    # Create/reuse group with the socket's GID so shannon can access it
    if getent group "$sock_gid" &>/dev/null; then
        DOCKER_GROUP=$(getent group "$sock_gid" | cut -d: -f1)
    else
        groupadd -g "$sock_gid" dockerhost 2>/dev/null || true
        DOCKER_GROUP="dockerhost"
    fi
    usermod -aG "$DOCKER_GROUP" shannon 2>/dev/null || true

    # Verify Docker access as shannon
    if su -s /bin/bash -c "sg ${DOCKER_GROUP} -c 'docker info'" shannon &>/dev/null; then
        log "Docker terhubung via host socket (group: ${DOCKER_GROUP})."
    else
        # Fallback: adjust socket permissions directly
        chmod 666 "$socket" 2>/dev/null || true
        if su -s /bin/bash -c "docker info" shannon &>/dev/null; then
            log "Docker terhubung (socket permissions adjusted)."
            DOCKER_GROUP=""
        else
            err "Tidak bisa terhubung ke Docker daemon."
            err "Pastikan Docker berjalan di host."
            exit 1
        fi
    fi
}

# --- 2. Configure .env from environment variables ---
configure_env() {
    if [[ -f "$ENV_FILE" ]] && ! grep -q 'your-api-key-here' "$ENV_FILE" 2>/dev/null; then
        info ".env sudah dikonfigurasi."
        return
    fi

    if [[ -n "${SHANNON_AI_API_KEY:-}" ]]; then
        local model="${SHANNON_AI_MODEL:-anthropic:claude-sonnet-4-6}"
        info "Mengkonfigurasi .env dari environment variables..."

        {
            printf '%s\n' "SHANNON_AI_API_KEY=${SHANNON_AI_API_KEY}"
            printf '%s\n' "SHANNON_AI_MODEL=${model}"
            if [[ -n "${SHANNON_AI_BASE_URL:-}" ]]; then
                printf '%s\n' "SHANNON_AI_BASE_URL=${SHANNON_AI_BASE_URL}"
            fi
        } > "$ENV_FILE"

        chown shannon:shannon "$ENV_FILE"
        chmod 600 "$ENV_FILE"
        log ".env configured (model: ${model})"
    else
        warn "SHANNON_AI_API_KEY tidak di-set."
        warn "Set via environment variable atau edit ${ENV_FILE}"

        if [[ ! -f "$ENV_FILE" ]]; then
            cp "${SHANNON_HOME}/.env.template" "$ENV_FILE" 2>/dev/null || true
            chown shannon:shannon "$ENV_FILE" 2>/dev/null || true
            chmod 600 "$ENV_FILE" 2>/dev/null || true
        fi
    fi
}

# --- 3. Start Temporal ---
start_temporal() {
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'shannon-temporal'; then
        info "Temporal sudah berjalan."
        return
    fi

    info "Starting Temporal service..."

    if [[ -n "${DOCKER_GROUP:-}" ]]; then
        su -s /bin/bash -c "sg ${DOCKER_GROUP} -c 'cd ${SHANNON_HOME} && docker compose up -d'" shannon 2>&1
    else
        su -s /bin/bash -c "cd ${SHANNON_HOME} && docker compose up -d" shannon 2>&1
    fi

    info "Menunggu Temporal healthy..."
    local waited=0
    while [[ $waited -lt 60 ]]; do
        if docker exec shannon-temporal temporal operator cluster health \
            --address localhost:7233 &>/dev/null; then
            log "Temporal healthy."
            return
        fi
        sleep 3
        waited=$((waited + 3))
    done

    warn "Temporal belum healthy, tapi mungkin perlu waktu lebih."
}

# --- 4. Show status ---
show_status() {
    echo ""
    echo "============================================"
    echo "  Shannon Ready"
    echo "============================================"

    local version
    version=$(su -s /bin/bash -c "cd ${SHANNON_HOME} && ./shannon version" shannon 2>/dev/null) || version="unknown"

    echo "  Version  : ${version}"
    echo "  User     : shannon"
    echo "  Directory: ${SHANNON_HOME}"
    echo ""
    echo "  Jalankan pentest:"
    echo "    ./shannon start -u https://target.com -r /home/shannon/target"
    echo ""
    echo "============================================"
    echo ""
}

# --- Main ---
DOCKER_GROUP=""
setup_docker
configure_env
start_temporal
show_status

# Drop privileges to shannon user and exec the CMD
if [[ -n "${DOCKER_GROUP}" ]]; then
    exec su -s /bin/bash -c "cd ${SHANNON_HOME} && sg ${DOCKER_GROUP} -c '$*'" shannon
else
    exec su -s /bin/bash -c "cd ${SHANNON_HOME} && $*" shannon
fi
