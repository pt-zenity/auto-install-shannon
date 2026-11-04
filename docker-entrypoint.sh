#!/usr/bin/env bash
# =============================================================================
# docker-entrypoint.sh — Shannon container entrypoint
# =============================================================================
# Handles Docker-in-Docker startup, .env configuration from environment
# variables, and drops privileges to the 'shannon' user.
# =============================================================================

set -euo pipefail

ENV_FILE="/home/shannon/shannon/.env"
SHANNON_HOME="/home/shannon/shannon"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
info() { echo -e "${CYAN}[i]${NC} $*"; }

# --- 1. Start Docker daemon (DinD) ---
start_docker() {
    if docker info &>/dev/null; then
        info "Docker daemon sudah berjalan."
        return
    fi

    info "Starting Docker daemon..."
    dockerd > /var/log/dockerd.log 2>&1 &

    # Wait for Docker to be ready (max 30s)
    local waited=0
    while [[ $waited -lt 30 ]]; do
        if docker info &>/dev/null; then
            log "Docker daemon ready."
            return
        fi
        sleep 1
        waited=$((waited + 1))
    done

    echo "ERROR: Docker daemon gagal start. Log:"
    tail -20 /var/log/dockerd.log
    exit 1
}

# --- 2. Configure .env from environment variables ---
configure_env() {
    # Skip if .env already exists and has real values
    if [[ -f "$ENV_FILE" ]] && ! grep -q 'your-api-key-here' "$ENV_FILE" 2>/dev/null; then
        info ".env sudah dikonfigurasi."
        return
    fi

    # Build .env from environment variables
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
        warn "Set via: docker run -e SHANNON_AI_API_KEY=your-key ..."
        warn "Atau edit ${ENV_FILE} secara manual setelah masuk."

        # Copy template if no .env exists
        if [[ ! -f "$ENV_FILE" ]]; then
            cp "${SHANNON_HOME}/.env.template" "$ENV_FILE"
            chown shannon:shannon "$ENV_FILE"
            chmod 600 "$ENV_FILE"
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
    su -s /bin/bash -c "cd ${SHANNON_HOME} && sg docker -c 'docker compose up -d'" shannon 2>&1

    # Wait for healthy (max 60s)
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
start_docker
configure_env
start_temporal
show_status

# Drop privileges to shannon user and exec the CMD
exec su -s /bin/bash -c "cd ${SHANNON_HOME} && exec $*" shannon
