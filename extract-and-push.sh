#!/usr/bin/env bash
# =============================================================================
# Extract source code dari Docker image dan push ke GitHub private repo
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[OK]${NC} $*"
}
warn() {
    echo -e "${YELLOW}[!!]${NC} $*"
}
err() {
    echo -e "${RED}[ERR]${NC} $*"
}
info() {
    echo -e "${CYAN}[i]${NC} $*"
}

# --- Config ---
DOCKER_IMAGE="inacash/reconcile-switching-qris-back-end:1.1.6-amd64"
GITHUB_USER="pt-zenity"
REPO_NAME="reconcile-switching-qris-back-end"
EXTRACT_DIR="/tmp/extract-qris-$$"
SOURCE_DIR="/tmp/qris-source-$$"

echo ""
echo "============================================"
echo "  Docker Image → GitHub Private Repo"
echo "============================================"
echo "  Image : ${DOCKER_IMAGE}"
echo "  Target: ${GITHUB_USER}/${REPO_NAME} (private)"
echo "============================================"
echo ""

# --- 1. Collect tokens ---
if [[ -n "${DOCKER_TOKEN:-}" ]]; then
    info "Docker token dari environment variable."
else
    read -rsp "Docker Hub Token (dckr_pat_...): " DOCKER_TOKEN; echo
fi

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    info "GitHub token dari environment variable."
else
    read -rsp "GitHub PAT (ghp_... atau github_pat_...): " GITHUB_TOKEN; echo
fi

if [[ -z "$DOCKER_TOKEN" ]]; then
    err "Docker token kosong."; exit 1
fi
if [[ -z "$GITHUB_TOKEN" ]]; then
    err "GitHub token kosong."; exit 1
fi

# --- 2. Login Docker Hub ---
info "Login ke Docker Hub..."
echo "$DOCKER_TOKEN" | docker login --username inacash --password-stdin 2>&1
log "Docker Hub login OK."

# --- 3. Pull image ---
info "Pulling image ${DOCKER_IMAGE}..."
docker pull "$DOCKER_IMAGE"
log "Image pulled."

# --- 4. Extract filesystem ---
info "Extracting filesystem dari image..."
mkdir -p "$EXTRACT_DIR"
docker create --name extract-src-$$ "$DOCKER_IMAGE" 2>/dev/null
docker export extract-src-$$ | tar -xf - -C "$EXTRACT_DIR"
docker rm extract-src-$$ >/dev/null
log "Filesystem extracted ke ${EXTRACT_DIR}"

# --- 5. Find source code ---
info "Mencari source code..."
mkdir -p "$SOURCE_DIR"

# Common locations for app source code in Docker images
if [[ -d "${EXTRACT_DIR}/app" ]]; then
    cp -a "${EXTRACT_DIR}/app/." "$SOURCE_DIR/"
    log "Source ditemukan di /app"
elif [[ -d "${EXTRACT_DIR}/src" ]]; then
    cp -a "${EXTRACT_DIR}/src/." "$SOURCE_DIR/"
    log "Source ditemukan di /src"
elif [[ -d "${EXTRACT_DIR}/opt/app" ]]; then
    cp -a "${EXTRACT_DIR}/opt/app/." "$SOURCE_DIR/"
    log "Source ditemukan di /opt/app"
elif [[ -d "${EXTRACT_DIR}/home/app" ]]; then
    cp -a "${EXTRACT_DIR}/home/app/." "$SOURCE_DIR/"
    log "Source ditemukan di /home/app"
else
    warn "Lokasi source code tidak ditemukan secara otomatis."
    echo ""
    echo "Isi root filesystem:"
    ls -la "$EXTRACT_DIR"
    echo ""
    read -rp "Masukkan path relatif source code (contoh: app atau var/www): " custom_path
    if [[ -d "${EXTRACT_DIR}/${custom_path}" ]]; then
        cp -a "${EXTRACT_DIR}/${custom_path}/." "$SOURCE_DIR/"
        log "Source dari /${custom_path}"
    else
        err "Path /${custom_path} tidak ditemukan."
        exit 1
    fi
fi

# --- 6. Also save Dockerfile info ---
info "Menyimpan metadata image..."
docker inspect "$DOCKER_IMAGE" > "${SOURCE_DIR}/docker-inspect.json" 2>/dev/null || true
docker history "$DOCKER_IMAGE" --no-trunc > "${SOURCE_DIR}/docker-history.txt" 2>/dev/null || true

# --- 7. Show what we got ---
echo ""
info "Isi source code:"
ls -la "$SOURCE_DIR" | head -20
file_count=$(find "$SOURCE_DIR" -type f | wc -l)
echo "  Total: ${file_count} files"
echo ""

# --- 8. Init git repo ---
info "Initializing git repository..."
cd "$SOURCE_DIR"

# Remove files that shouldn't be in git
rm -rf .git node_modules vendor __pycache__ .env docker-inspect.json docker-history.txt 2>/dev/null || true

git init
git branch -m main
git add .
git commit -m "Extract from Docker image ${DOCKER_IMAGE}"
log "Git commit created."

# --- 9. Create GitHub private repo ---
info "Membuat repo private di GitHub..."
REPO_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${REPO_NAME}.git"

# Create repo via GitHub API
curl -s -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    https://api.github.com/user/repos \
    -d "{\"name\":\"${REPO_NAME}\",\"private\":true,\"description\":\"Reconcile Switching QRIS Back-End v1.1.6\"}" \
    > /tmp/gh-create-response.json 2>&1

if grep -q '"full_name"' /tmp/gh-create-response.json; then
    log "Repo private dibuat: github.com/${GITHUB_USER}/${REPO_NAME}"
elif grep -q 'already exists' /tmp/gh-create-response.json; then
    warn "Repo sudah ada, akan push ke existing repo."
else
    warn "Response dari GitHub:"
    cat /tmp/gh-create-response.json
fi
rm -f /tmp/gh-create-response.json

# --- 10. Push ---
info "Pushing ke GitHub..."
git remote add origin "$REPO_URL" 2>/dev/null || git remote set-url origin "$REPO_URL"
git push -u origin main --force 2>&1
log "Push berhasil!"

# --- 11. Cleanup ---
info "Cleaning up..."
rm -rf "$EXTRACT_DIR"
docker logout 2>/dev/null || true

echo ""
echo "============================================"
echo "  Selesai!"
echo "============================================"
echo "  Repo  : https://github.com/${GITHUB_USER}/${REPO_NAME}"
echo "  Branch: main"
echo "  Source : extracted from ${DOCKER_IMAGE}"
echo "============================================"
echo ""
