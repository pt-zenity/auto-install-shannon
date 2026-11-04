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

## Quick Start

```bash
# Download script
wget https://raw.githubusercontent.com/pt-zenity/auto-install-shannon/main/auto-install-shannon.sh
chmod +x auto-install-shannon.sh

# Jalankan sebagai root
sudo ./auto-install-shannon.sh
```

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

- Ubuntu 24.04 LTS (x86_64 atau aarch64)
- RAM minimal 4GB (rekomendasi 8GB+)
- Disk minimal 10GB tersedia
- Koneksi internet
- Akses root atau sudo

## Referensi

- [Shannon Repository](https://github.com/KeygraphHQ/shannon)
- [Shannon AI Providers](https://github.com/KeygraphHQ/shannon/blob/main/docs/ai-providers.md)
- [Shannon Configuration](https://github.com/KeygraphHQ/shannon/blob/main/docs/configuration.md)
- [Shannon Platforms](https://github.com/KeygraphHQ/shannon/blob/main/docs/platforms.md)

## License

MIT
