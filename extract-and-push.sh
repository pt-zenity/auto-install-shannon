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
EXTRACT_DIR="/home/shannon/shannon/ina"

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

# --- 4. Extract seluruh isi image ---
info "Extracting seluruh isi image ke ${EXTRACT_DIR}..."
mkdir -p "$EXTRACT_DIR"
docker create --name extract-src-$$ "$DOCKER_IMAGE" 2>/dev/null
docker export extract-src-$$ | tar -xf - -C "$EXTRACT_DIR"
docker rm extract-src-$$ >/dev/null
log "Seluruh isi image extracted ke ${EXTRACT_DIR}"

# --- 5. Show contents ---
echo ""
info "Isi ${EXTRACT_DIR}:"
ls -la "$EXTRACT_DIR" | head -30
file_count=$(find "$EXTRACT_DIR" -type f | wc -l)
dir_count=$(find "$EXTRACT_DIR" -type d | wc -l)
total_size=$(du -sh "$EXTRACT_DIR" | cut -f1)
echo ""
echo "  Files: ${file_count} | Dirs: ${dir_count} | Size: ${total_size}"
echo ""

# --- 6. Save metadata ---
info "Menyimpan metadata image..."
docker inspect "$DOCKER_IMAGE" > "${EXTRACT_DIR}/docker-inspect.json" 2>/dev/null || true
docker history "$DOCKER_IMAGE" --no-trunc > "${EXTRACT_DIR}/docker-history.txt" 2>/dev/null || true

# --- 7. Init git & push ---
info "Initializing git repository..."
cd "$EXTRACT_DIR"

git init
git branch -m main
git add .
git commit -m "Extract from Docker image ${DOCKER_IMAGE}"
log "Git commit created."

info "Membuat repo private di GitHub..."
REPO_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${REPO_NAME}.git"

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

info "Pushing ke GitHub..."
git remote add origin "$REPO_URL" 2>/dev/null || git remote set-url origin "$REPO_URL"
git push -u origin main --force 2>&1
log "Push berhasil!"

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
