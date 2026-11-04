#!/usr/bin/env bash
# ============================================================================
# Shannon Auto-Installer for Ubuntu 24.04 LTS
# ============================================================================
# Script ini menginstal Shannon (AI Pentester) dari source build sesuai
# dokumentasi resmi: https://github.com/KeygraphHQ/shannon
#
# Prerequisites: Ubuntu 24.04 LTS, akses root atau sudo, koneksi internet
#
# Usage:
#   chmod +x auto-install-shannon.sh
#   sudo ./auto-install-shannon.sh
#
# Setelah selesai, jalankan Shannon sebagai user non-root:
#   su - shannon
#   cd ~/shannon
#   ./shannon start -u https://target.com -r /path/to/repo
# ============================================================================

set -euo pipefail

# --- Warna output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; }
info() { echo -e "${CYAN}[i]${NC} $*"; }

# --- Variabel ---
SHANNON_USER="${SHANNON_USER:-shannon}"
SHANNON_HOME="/home/${SHANNON_USER}/shannon"
SHANNON_REPO="https://github.com/KeygraphHQ/shannon.git"
SHANNON_BRANCH="main"
NODE_MAJOR=22
REQUIRED_RAM_MB=4096
REQUIRED_DISK_GB=10

# ============================================================================
# 1. Preflight checks
# ============================================================================
preflight() {
    echo ""
    echo "============================================"
    echo "  Shannon Auto-Installer"
    echo "  Target: Ubuntu 24.04 LTS"
    echo "============================================"
    echo ""

    # Root check
    if [[ $EUID -ne 0 ]]; then
        err "Script ini harus dijalankan sebagai root atau dengan sudo."
        exit 1
    fi

    # OS check
    if ! grep -q 'Ubuntu' /etc/os-release 2>/dev/null; then
        err "OS bukan Ubuntu. Script ini dirancang untuk Ubuntu 24.04 LTS."
        exit 1
    fi
    local os_version
    os_version=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    info "OS: Ubuntu ${os_version}"

    # Architecture
    local arch
    arch=$(uname -m)
    if [[ "$arch" != "x86_64" && "$arch" != "aarch64" ]]; then
        err "Arsitektur ${arch} tidak didukung. Hanya x86_64 dan aarch64."
        exit 1
    fi
    info "Arsitektur: ${arch}"

    # RAM check
    local ram_mb
    ram_mb=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
    if [[ $ram_mb -lt $REQUIRED_RAM_MB ]]; then
        warn "RAM ${ram_mb}MB di bawah rekomendasi minimum ${REQUIRED_RAM_MB}MB."
        warn "Shannon mungkin tetap berjalan tapi performa bisa terbatas."
    else
        info "RAM: ${ram_mb}MB"
    fi

    # Disk check
    local disk_gb
    disk_gb=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    if [[ $disk_gb -lt $REQUIRED_DISK_GB ]]; then
        err "Disk tersedia ${disk_gb}GB, minimum ${REQUIRED_DISK_GB}GB diperlukan."
        exit 1
    fi
    info "Disk tersedia: ${disk_gb}GB"

    # CPU
    local cpus
    cpus=$(nproc)
    info "CPU cores: ${cpus}"

    log "Preflight checks passed."
    echo ""
}

# ============================================================================
# 2. Install system dependencies
# ============================================================================
install_dependencies() {
    info "Menginstal system dependencies..."

    apt-get update -qq

    # Essential packages
    apt-get install -y -qq \
        curl \
        wget \
        git \
        ca-certificates \
        gnupg \
        lsb-release \
        build-essential \
        > /dev/null 2>&1

    log "System dependencies terinstal."
}

# ============================================================================
# 3. Install Docker (jika belum ada)
# ============================================================================
install_docker() {
    if command -v docker &>/dev/null; then
        local docker_ver
        docker_ver=$(docker --version | awk '{print $3}' | tr -d ',')
        info "Docker sudah terinstal: ${docker_ver}"
    else
        info "Menginstal Docker..."

        # Docker official GPG key
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
            | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg

        # Docker repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
            | tee /etc/apt/sources.list.d/docker.list > /dev/null

        apt-get update -qq
        apt-get install -y -qq \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin \
            > /dev/null 2>&1

        log "Docker terinstal."
    fi

    # Docker Compose check
    if docker compose version &>/dev/null; then
        local compose_ver
        compose_ver=$(docker compose version --short 2>/dev/null || docker compose version | awk '{print $NF}')
        info "Docker Compose: ${compose_ver}"
    else
        err "Docker Compose tidak tersedia."
        exit 1
    fi

    # Start and enable Docker
    if command -v systemctl &>/dev/null; then
        systemctl start docker 2>/dev/null || true
        systemctl enable docker 2>/dev/null || true
    else
        # Non-systemd environment
        if ! docker info &>/dev/null; then
            dockerd --host unix:///var/run/docker.sock > /tmp/dockerd.log 2>&1 &
            sleep 3
        fi
    fi

    # Verify Docker is running
    if docker info &>/dev/null; then
        log "Docker daemon berjalan."
    else
        err "Docker daemon gagal start. Periksa: journalctl -u docker"
        exit 1
    fi
}

# ============================================================================
# 4. Install Node.js 22 (jika belum ada atau versi < 18)
# ============================================================================
install_nodejs() {
    local need_install=false

    if command -v node &>/dev/null; then
        local node_major
        node_major=$(node --version | cut -d'.' -f1 | tr -d 'v')
        if [[ $node_major -lt 18 ]]; then
            warn "Node.js v${node_major} terlalu lama. Menginstal Node.js ${NODE_MAJOR}..."
            need_install=true
        else
            info "Node.js sudah terinstal: $(node --version)"
        fi
    else
        need_install=true
    fi

    if $need_install; then
        info "Menginstal Node.js ${NODE_MAJOR}..."

        curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - > /dev/null 2>&1
        apt-get install -y -qq nodejs > /dev/null 2>&1

        log "Node.js $(node --version) terinstal."
    fi

    # Install/enable corepack for pnpm
    if command -v corepack &>/dev/null; then
        corepack enable 2>/dev/null || true
        info "Corepack enabled."
    else
        warn "Corepack tidak tersedia, menginstal pnpm secara manual..."
        npm install -g pnpm > /dev/null 2>&1
    fi
}

# ============================================================================
# 5. Create dedicated user
# ============================================================================
create_user() {
    if id "$SHANNON_USER" &>/dev/null; then
        info "User '${SHANNON_USER}' sudah ada."
    else
        info "Membuat user '${SHANNON_USER}'..."
        useradd -m -s /bin/bash "$SHANNON_USER"
        log "User '${SHANNON_USER}' dibuat."
    fi

    # Add to docker group
    usermod -aG docker "$SHANNON_USER"
    log "User '${SHANNON_USER}' ditambahkan ke grup docker."

    # Ensure home directory exists and is owned by the user
    mkdir -p "/home/${SHANNON_USER}"
    chown "${SHANNON_USER}:${SHANNON_USER}" "/home/${SHANNON_USER}"
}

# ============================================================================
# 6. Clone repository
# ============================================================================
clone_repo() {
    if [[ -d "${SHANNON_HOME}/.git" ]]; then
        info "Repository sudah ada di ${SHANNON_HOME}."
        info "Menarik update terbaru..."
        su -s /bin/bash -c "cd ${SHANNON_HOME} && git pull origin ${SHANNON_BRANCH}" "$SHANNON_USER" 2>&1
    else
        # If directory exists but is not a git repo, back it up instead of deleting
        if [[ -d "${SHANNON_HOME}" ]]; then
            local backup="${SHANNON_HOME}.bak.$(date +%s)"
            warn "Directory ${SHANNON_HOME} ada tapi bukan git repo. Backup ke ${backup}"
            mv "${SHANNON_HOME}" "${backup}"
        fi

        info "Cloning Shannon dari ${SHANNON_REPO}..."
        su -s /bin/bash -c "git clone --depth 1 -b ${SHANNON_BRANCH} ${SHANNON_REPO} ${SHANNON_HOME}" "$SHANNON_USER" 2>&1
    fi

    log "Repository siap di ${SHANNON_HOME}"

    # Show version
    local commit
    commit=$(su -s /bin/bash -c "cd ${SHANNON_HOME} && git log --oneline -1" "$SHANNON_USER" 2>/dev/null || echo "unknown")
    info "Commit: ${commit}"
}

# ============================================================================
# 7. Install dependencies & build
# ============================================================================
build_shannon() {
    # Detect Node.js and pnpm paths for the su environment
    local node_bin=""
    if command -v node &>/dev/null; then
        node_bin=$(dirname "$(command -v node)")
    fi
    local pnpm_bin=""
    if command -v pnpm &>/dev/null; then
        pnpm_bin=$(dirname "$(command -v pnpm)")
    elif command -v corepack &>/dev/null; then
        pnpm_bin=$(dirname "$(command -v corepack)")
    fi

    if [[ -z "$node_bin" ]]; then
        err "Node.js tidak ditemukan di PATH. Pastikan install_nodejs() berhasil."
        exit 1
    fi
    if [[ -z "$pnpm_bin" ]]; then
        warn "pnpm/corepack tidak ditemukan di PATH, menggunakan node_bin sebagai fallback."
        pnpm_bin="$node_bin"
    fi

    # Build PATH that includes Node.js, pnpm, and corepack for the shannon user
    local build_path="${node_bin}:${pnpm_bin}:/usr/local/bin:/usr/bin:/bin"

    info "Menginstal dependencies (pnpm install)..."
    su -s /bin/bash -c "export PATH='${build_path}:\$PATH' && cd ${SHANNON_HOME} && corepack enable 2>/dev/null; pnpm install" "$SHANNON_USER" 2>&1

    info "Building Shannon (pnpm build)..."
    su -s /bin/bash -c "export PATH='${build_path}:\$PATH' && cd ${SHANNON_HOME} && pnpm build" "$SHANNON_USER" 2>&1

    # Verify build artifacts
    if [[ -f "${SHANNON_HOME}/apps/cli/dist/index.mjs" && \
          -f "${SHANNON_HOME}/apps/worker/dist/temporal/worker.js" ]]; then
        log "Build berhasil."
    else
        err "Build artifacts tidak ditemukan. Build mungkin gagal."
        exit 1
    fi

    # Verify CLI
    local version
    if version=$(su -s /bin/bash -c "cd ${SHANNON_HOME} && ./shannon version" "$SHANNON_USER" 2>&1); then
        log "Shannon CLI: ${version}"
    else
        err "Shannon CLI gagal: ${version}"
        exit 1
    fi
}

# ============================================================================
# 8. Configure environment
# ============================================================================
configure_env() {
    local env_file="${SHANNON_HOME}/.env"

    if [[ -f "$env_file" ]]; then
        warn ".env sudah ada, tidak ditimpa."
        info "Edit manual jika perlu: ${env_file}"
        return
    fi

    info "Membuat konfigurasi .env..."

    # Prompt for provider choice
    echo ""
    echo "=== Konfigurasi AI Provider ==="
    echo ""
    echo "  1) Anthropic (default, model: claude-sonnet-4-6)"
    echo "  2) OpenAI (model: gpt-6-sol)"
    echo "  3) xAI / Grok (model: grok-4.7)"
    echo "  4) Kagiro - Anthropic format (proxy, model: claude-haiku-5-5)"
    echo "  5) Kagiro - OpenAI format (proxy)"
    echo "  6) Custom / Other provider"
    echo "  7) Skip (isi manual nanti)"
    echo ""
    read -rp "Pilih provider [1-7]: " provider_choice

    # Validate API key is not empty for provider options that require it
    validate_key() {
        if [[ -z "${1:-}" ]]; then
            err "API key tidak boleh kosong."
            exit 1
        fi
    }

    # Write .env safely — printf '%s\n' prevents shell expansion of special chars
    # in API keys (e.g. $, backticks, backslashes)
    write_env() {
        printf '%s\n' "$@" > "$env_file"
    }

    case "${provider_choice}" in
        1)
            read -rsp "Masukkan ANTHROPIC API KEY: " api_key; echo
            validate_key "$api_key"
            write_env \
                "SHANNON_AI_API_KEY=${api_key}" \
                "SHANNON_AI_MODEL=anthropic:claude-sonnet-4-6"
            ;;
        2)
            read -rsp "Masukkan OPENAI API KEY: " api_key; echo
            validate_key "$api_key"
            write_env \
                "SHANNON_AI_API_KEY=${api_key}" \
                "SHANNON_AI_MODEL=openai:gpt-6-sol"
            ;;
        3)
            read -rsp "Masukkan XAI API KEY: " api_key; echo
            validate_key "$api_key"
            write_env \
                "SHANNON_AI_API_KEY=${api_key}" \
                "SHANNON_AI_MODEL=xai:grok-4.7"
            ;;
        4)
            read -rsp "Masukkan KAGIRO API KEY (kagiro-...): " api_key; echo
            validate_key "$api_key"
            read -rp "Model (default: claude-haiku-5-5): " model_id
            model_id="${model_id:-claude-haiku-5-5}"
            write_env \
                "SHANNON_AI_API_KEY=${api_key}" \
                "SHANNON_AI_MODEL=anthropic:${model_id}" \
                "SHANNON_AI_BASE_URL=https://api.kagiro.net"
            ;;
        5)
            read -rsp "Masukkan KAGIRO API KEY (kagiro-...): " api_key; echo
            validate_key "$api_key"
            read -rp "Model ID (contoh: gpt-4o): " model_id
            if [[ -z "$model_id" ]]; then
                err "Model ID tidak boleh kosong untuk Kagiro OpenAI format."
                err "Contoh model: gpt-4o, claude-haiku-5-5"
                exit 1
            fi
            write_env \
                "SHANNON_AI_API_KEY=${api_key}" \
                "SHANNON_AI_MODEL=openai:${model_id}" \
                "SHANNON_AI_BASE_URL=https://api.kagiro.net/v1"
            ;;
        6)
            read -rp "Provider ID (contoh: openrouter): " provider_id
            if [[ -z "$provider_id" ]]; then
                err "Provider ID tidak boleh kosong."
                exit 1
            fi
            read -rp "Model ID (contoh: moonshotai/kimi-k3): " model_id
            if [[ -z "$model_id" ]]; then
                err "Model ID tidak boleh kosong."
                exit 1
            fi
            read -rsp "API KEY: " api_key; echo
            validate_key "$api_key"
            read -rp "Base URL (kosongkan jika default): " base_url
            if [[ -n "$base_url" ]]; then
                write_env \
                    "SHANNON_AI_API_KEY=${api_key}" \
                    "SHANNON_AI_MODEL=${provider_id}:${model_id}" \
                    "SHANNON_AI_BASE_URL=${base_url}"
            else
                write_env \
                    "SHANNON_AI_API_KEY=${api_key}" \
                    "SHANNON_AI_MODEL=${provider_id}:${model_id}"
            fi
            ;;
        7|*)
            if [[ -f "${SHANNON_HOME}/.env.example" ]]; then
                cp "${SHANNON_HOME}/.env.example" "$env_file"
                warn "Menggunakan .env.example sebagai template."
                warn "Edit ${env_file} dan isi API key sebelum menjalankan Shannon."
            else
                err ".env.example tidak ditemukan di ${SHANNON_HOME}."
                err "Buat file .env secara manual. Lihat: https://github.com/KeygraphHQ/shannon/blob/main/docs/ai-providers.md"
                return
            fi
            ;;
    esac

    chown "${SHANNON_USER}:${SHANNON_USER}" "$env_file"
    chmod 600 "$env_file"
    log "Konfigurasi .env tersimpan (mode 600, hanya owner bisa baca)."
}

# ============================================================================
# 9. Start Docker services (Temporal)
# ============================================================================
start_services() {
    info "Menjalankan Docker services (Temporal)..."

    # Use sg to activate the docker group without requiring re-login
    su -s /bin/bash -c "sg docker -c 'cd ${SHANNON_HOME} && docker compose up -d'" "$SHANNON_USER" 2>&1

    info "Menunggu Temporal healthy (max 60 detik)..."
    local waited=0
    while [[ $waited -lt 60 ]]; do
        if docker exec shannon-temporal temporal operator cluster health \
            --address localhost:7233 &>/dev/null; then
            log "Temporal healthy."
            return
        fi
        sleep 5
        waited=$((waited + 5))
        echo -n "."
    done
    echo ""

    # Check status even if health check didn't pass
    local status
    status=$(docker inspect -f '{{.State.Status}}' shannon-temporal 2>/dev/null) || status="not found"
    if [[ "$status" == "running" ]]; then
        warn "Temporal berjalan tapi health check belum pass. Mungkin perlu waktu lebih lama."
    else
        err "Temporal container status: ${status}"
        err "Periksa log: docker logs shannon-temporal"
    fi
}

# ============================================================================
# 10. Health checks
# ============================================================================
health_check() {
    # Disable exit-on-error for diagnostics — health checks should report, not crash
    set +e

    echo ""
    echo "=== Health Checks ==="
    echo ""

    # Docker
    if docker info &>/dev/null; then
        log "Docker daemon: running"
    else
        err "Docker daemon: not running"
    fi

    # Temporal container
    local temporal_status
    temporal_status=$(docker inspect -f '{{.State.Status}}' shannon-temporal 2>/dev/null) || temporal_status="not found"
    if [[ "$temporal_status" == "running" ]]; then
        log "Temporal container: running"
    else
        err "Temporal container: ${temporal_status}"
    fi

    # Temporal health
    if docker exec shannon-temporal temporal operator cluster health \
        --address localhost:7233 &>/dev/null; then
        log "Temporal health: healthy"
    else
        warn "Temporal health: not yet healthy (may need more time)"
    fi

    # Temporal ports
    if ss -tlnp 2>/dev/null | grep -q ':7233' || \
       netstat -tlnp 2>/dev/null | grep -q ':7233'; then
        log "Temporal gRPC (port 7233): listening"
    else
        warn "Temporal gRPC (port 7233): not detected (may be mapped to container only)"
    fi

    if ss -tlnp 2>/dev/null | grep -q ':8233' || \
       netstat -tlnp 2>/dev/null | grep -q ':8233'; then
        log "Temporal Web UI (port 8233): listening"
    else
        warn "Temporal Web UI (port 8233): not detected"
    fi

    # Shannon CLI
    local shannon_ver
    if shannon_ver=$(su -s /bin/bash -c "cd ${SHANNON_HOME} && ./shannon version" "$SHANNON_USER" 2>&1); then
        log "Shannon CLI: ${shannon_ver}"
    else
        err "Shannon CLI: failed — ${shannon_ver}"
    fi

    # .env check
    if [[ -f "${SHANNON_HOME}/.env" ]]; then
        if grep -q 'your-api-key-here\|YOUR_KEY_HERE' "${SHANNON_HOME}/.env" 2>/dev/null; then
            warn ".env: template belum diisi. Edit ${SHANNON_HOME}/.env"
        else
            log ".env: configured"
        fi
    else
        err ".env: tidak ditemukan"
    fi

    # Error logs (only check if container exists)
    if [[ "$temporal_status" == "running" ]]; then
        local error_count
        error_count=$(docker logs shannon-temporal 2>&1 | grep -ci 'fatal\|panic' || true)
        error_count="${error_count:-0}"
        if [[ "$error_count" -gt 0 ]]; then
            warn "Temporal log: ${error_count} fatal/panic entries (periksa: docker logs shannon-temporal)"
        else
            log "Temporal log: clean"
        fi
    fi

    # Re-enable exit-on-error
    set -e
}

# ============================================================================
# 11. Print final report
# ============================================================================
final_report() {
    echo ""
    echo "============================================"
    echo "  Shannon Installation Complete"
    echo "============================================"
    echo ""

    local shannon_ver
    shannon_ver=$(su -s /bin/bash -c "cd ${SHANNON_HOME} && ./shannon version" "$SHANNON_USER" 2>/dev/null) || shannon_ver="unknown"
    local docker_ver
    docker_ver=$(docker --version | awk '{print $3}' | tr -d ',')
    local node_ver
    node_ver=$(node --version 2>/dev/null || echo "unknown")
    local pnpm_ver
    local report_path
    report_path="$(dirname "$(command -v node 2>/dev/null || echo /usr/bin/node)")"
    pnpm_ver=$(su -s /bin/bash -c "export PATH='${report_path}:/usr/local/bin:\$PATH' && pnpm --version" "$SHANNON_USER" 2>/dev/null || echo "unknown")

    echo "  Shannon    : ${shannon_ver}"
    echo "  Docker     : ${docker_ver}"
    echo "  Node.js    : ${node_ver}"
    echo "  pnpm       : ${pnpm_ver}"
    echo "  User       : ${SHANNON_USER}"
    echo "  Directory  : ${SHANNON_HOME}"
    echo "  Config     : ${SHANNON_HOME}/.env"
    echo ""
    echo "--------------------------------------------"
    echo "  Perintah Utama (jalankan sebagai ${SHANNON_USER}):"
    echo "--------------------------------------------"
    echo ""
    echo "  # Login sebagai user shannon"
    echo "  su - ${SHANNON_USER}"
    echo "  cd ~/shannon"
    echo ""
    echo "  # Jalankan pentest"
    echo "  ./shannon start -u https://target.com -r /path/to/repo"
    echo ""
    echo "  # Monitor"
    echo "  ./shannon logs              # log real-time"
    echo "  ./shannon status            # status scan"
    echo "  ./shannon scans             # list semua scan"
    echo "  open http://localhost:8233  # Temporal Web UI"
    echo ""
    echo "  # Stop"
    echo "  ./shannon stop              # stop satu scan"
    echo "  ./shannon stop --all        # stop semua scan"
    echo ""
    echo "  # Docker services"
    echo "  docker compose up -d        # start Temporal"
    echo "  docker compose down         # stop Temporal"
    echo "  docker compose ps           # status containers"
    echo ""
    echo "--------------------------------------------"
    echo "  Update Shannon:"
    echo "--------------------------------------------"
    echo ""
    echo "  cd ~/shannon"
    echo "  git pull origin main"
    echo "  pnpm install"
    echo "  pnpm build"
    echo ""
    echo "--------------------------------------------"
    echo "  Troubleshooting:"
    echo "--------------------------------------------"
    echo ""
    echo "  - Root error     : Jalankan sebagai '${SHANNON_USER}', bukan root"
    echo "  - Docker error   : Pastikan daemon aktif dan user di grup docker"
    echo "  - Temporal error : docker logs shannon-temporal"
    echo "  - API key error  : Edit ${SHANNON_HOME}/.env"
    echo "  - Cyber safeguard: Selesaikan verifikasi di provider AI"
    echo "    Anthropic: https://support.claude.com/en/articles/14604842"
    echo "    OpenAI: https://chatgpt.com/cyber"
    echo ""
    echo "  Dokumentasi lengkap: https://github.com/KeygraphHQ/shannon"
    echo ""
    echo "============================================"
}

# ============================================================================
# Main
# ============================================================================
main() {
    preflight
    install_dependencies
    install_docker
    install_nodejs
    create_user
    clone_repo
    build_shannon
    configure_env
    start_services
    health_check
    final_report
}

main "$@"
