# Auto-Install Shannon

Script otomatis untuk menginstal [Shannon AI Pentester](https://github.com/KeygraphHQ/shannon) dari source build pada **Ubuntu 24.04 LTS**.

## Fitur

- Preflight check (OS, CPU, RAM, disk, arsitektur)
- Install Docker, Node.js 22, pnpm secara otomatis
- Buat dedicated non-root user dengan akses Docker
- Clone repository resmi Shannon dan build dari source
- Wizard interaktif untuk konfigurasi AI provider (Anthropic, OpenAI, xAI, Kagiro, Custom)
- API key disimpan aman (file mode 600)
- Start Docker services (Temporal) dan tunggu healthy
- Health check lengkap (Docker, Temporal, Shannon CLI, port, log)
- Laporan akhir dengan perintah operasional

## Supported Providers

| Provider | Format |
|----------|--------|
| Anthropic | `anthropic:claude-sonnet-4-6` |
| OpenAI | `openai:gpt-6-sol` |
| xAI (Grok) | `xai:grok-4.7` |
| Kagiro (Anthropic) | `anthropic:claude-haiku-5-5` via `api.kagiro.net` |
| Kagiro (OpenAI) | `openai:<model>` via `api.kagiro.net/v1` |
| Custom | Any Pi harness provider |

## Quick Start — Script

```bash
# Download dan jalankan
wget https://raw.githubusercontent.com/pt-zenity/auto-install-shannon/main/auto-install-shannon.sh
chmod +x auto-install-shannon.sh
sudo ./auto-install-shannon.sh
```

## Quick Start — Docker

```bash
# Build image
docker build -t shannon-ready .

# Jalankan (mount Docker socket dari host, tanpa --privileged)
docker run -it \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e SHANNON_AI_API_KEY=your-api-key \
  -e SHANNON_AI_MODEL=anthropic:claude-sonnet-4-6 \
  shannon-ready

# Dengan Kagiro
docker run -it \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e SHANNON_AI_API_KEY=kagiro-your-key \
  -e SHANNON_AI_MODEL=anthropic:claude-haiku-5-5 \
  -e SHANNON_AI_BASE_URL=https://api.kagiro.net \
  shannon-ready

# Mount target repo untuk scanning
docker run -it \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e SHANNON_AI_API_KEY=your-api-key \
  -v /path/to/target-repo:/home/shannon/target:ro \
  -v shannon-workspaces:/home/shannon/shannon/workspaces \
  shannon-ready \
  ./shannon start -u https://target.com -r /home/shannon/target
```

### Deploy via ServerKit

1. Buat app Docker di ServerKit, hubungkan ke repo `pt-zenity/auto-install-shannon`
2. Tambahkan volume: `/var/run/docker.sock:/var/run/docker.sock`
3. Set environment variables: `SHANNON_AI_API_KEY`, `SHANNON_AI_MODEL`, `SHANNON_AI_BASE_URL`
4. Deploy

## Setelah Instalasi

```bash
# Login sebagai user shannon
su - shannon
cd ~/shannon

# Jalankan pentest
./shannon start -u https://target.com -r /path/to/repo

# Monitor
./shannon logs
./shannon status

# Stop
./shannon stop
```

## Requirements

**Script:**
- Ubuntu 24.04 LTS (x86_64 atau aarch64)
- RAM minimal 4GB (rekomendasi 8GB+)
- Disk minimal 10GB tersedia
- Koneksi internet
- Akses root atau sudo

**Docker:**
- Docker 20.10+ di host (container mount socket, bukan DinD)
- RAM minimal 4GB
- API key dari AI provider yang didukung

## Referensi

- [Shannon Repository](https://github.com/KeygraphHQ/shannon)
- [Shannon AI Providers](https://github.com/KeygraphHQ/shannon/blob/main/docs/ai-providers.md)
- [Shannon Configuration](https://github.com/KeygraphHQ/shannon/blob/main/docs/configuration.md)
- [Shannon Platforms](https://github.com/KeygraphHQ/shannon/blob/main/docs/platforms.md)

## License

MIT
