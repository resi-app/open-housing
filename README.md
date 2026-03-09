# OpenResiApp

Open-source web application for managing residential apartment buildings (bytove domy) in Slovakia. Built for building administrators, owners, and tenants.

## Features

- **Board** — Announcements with categories (info, urgent, event, maintenance)
- **Voting** — Weighted voting by ownership share, electronic and paper ballots, mandate delegation
- **Owner Management** — Users with role-based access (admin, owner, tenant, vote counter)
- **Documents** — Upload and share building documents
- **Settings** — Building configuration
- **Multi-language** — Slovak and English UI

## Quick Deploy (5 minutes)

You need a VPS with Docker installed (any provider — Hetzner, AWS, Azure, DigitalOcean).

```bash
# 1. Download compose file and env template
curl -O https://raw.githubusercontent.com/open-resiapp/open-resiapp/main/docker-compose.hub.yml
curl -O https://raw.githubusercontent.com/open-resiapp/open-resiapp/main/.env.production.example

# 2. Configure
cp .env.production.example .env
nano .env
# Fill in: APP_URL, APP_DOMAIN, POSTGRES_PASSWORD, NEXTAUTH_SECRET
# Generate secrets:
#   openssl rand -base64 32   (for POSTGRES_PASSWORD)
#   openssl rand -base64 64   (for NEXTAUTH_SECRET)

# 3. Deploy
docker compose -f docker-compose.hub.yml up -d

# 4. Create your admin account
docker compose -f docker-compose.hub.yml exec app npx tsx src/scripts/create-admin.ts --email admin@yourdomain.sk --name "Your Name"

# 5. Open https://yourdomain.sk and log in
```

That's it. Database migrations run automatically on startup. HTTPS is handled by Caddy.

## Update

```bash
docker compose -f docker-compose.hub.yml pull
docker compose -f docker-compose.hub.yml up -d
```

This pulls the latest image and restarts the app. Database migrations run automatically — no manual steps needed.

## Backup

### Local backup (included)

Download the backup script and add it to cron:

```bash
curl -O https://raw.githubusercontent.com/open-resiapp/open-resiapp/main/scripts/backup.sh
chmod +x backup.sh

# Test it
./backup.sh

# Add to cron (daily at 3 AM)
(crontab -l 2>/dev/null; echo "0 3 * * * cd $(pwd) && ./backup.sh >> /var/log/resiapp-backup.log 2>&1") | crontab -
```

### Remote backup (optional)

For off-server backups that survive even if your VPS is compromised:

| Provider | Tool | Setup script |
|----------|------|-------------|
| Hetzner Storage Box | BorgBackup | `backup-hetzner-setup.sh` |
| AWS S3 | Restic | `backup-aws-setup.sh` |
| Azure Blob Storage | Restic | `backup-azure-setup.sh` |

Download the setup script for your provider and follow the instructions:

```bash
# Example: Hetzner Storage Box
curl -O https://raw.githubusercontent.com/open-resiapp/open-resiapp/main/scripts/backup-hetzner-setup.sh
chmod +x backup-hetzner-setup.sh
# Add BORG_REPO, BORG_PASSPHRASE to .env, then:
./backup-hetzner-setup.sh
```

### Restore

```bash
curl -O https://raw.githubusercontent.com/open-resiapp/open-resiapp/main/scripts/restore.sh
chmod +x restore.sh

# From local backup
./restore.sh /backups/resiapp/daily/db_2026-03-09_030000.sql.gz

# From remote backup
./restore.sh list              # show available archives
./restore.sh borg latest       # restore latest borg archive
./restore.sh restic latest     # restore latest restic snapshot
```

## Development

### Prerequisites

- Node.js 20+
- PostgreSQL 16 (or Docker)

### Setup

```bash
git clone https://github.com/open-resiapp/open-resiapp.git
cd open-resiapp
npm install
docker compose up db        # start PostgreSQL
npm run db:generate
npm run db:migrate
npm run db:seed
npm run dev                 # http://localhost:3000
```

### Seed Credentials

| Role  | Email          | Password   |
|-------|----------------|------------|
| Admin | admin@test.sk  | Admin123!  |
| Owner | jan@test.sk    | Admin123!  |
| Owner | maria@test.sk  | Admin123!  |

### Scripts

| Command              | Description                    |
|----------------------|--------------------------------|
| `npm run dev`        | Start development server       |
| `npm run build`      | Build for production           |
| `npm run lint`       | Run ESLint                     |
| `npm run db:generate`| Generate Drizzle migrations    |
| `npm run db:migrate` | Run database migrations        |
| `npm run db:seed`    | Seed database with test data   |
| `npm run db:studio`  | Open Drizzle Studio            |

## Tech Stack

- **Next.js 16** (App Router) + TypeScript
- **Tailwind CSS**
- **PostgreSQL 16** + Drizzle ORM
- **NextAuth v5** (credentials provider)
- **next-intl** (i18n)
- **Docker** + Caddy

## Contributing

Contributions are welcome!

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Open a Pull Request

## License

[MIT License](LICENSE)