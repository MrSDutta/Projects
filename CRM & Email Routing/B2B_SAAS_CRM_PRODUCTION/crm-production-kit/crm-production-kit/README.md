# B2B CRM Production Kit
### Complete deployment guide for a new client instance

---

## What's in this kit

```
crm-production-kit/
├── README.md                    ← You are here
├── workflow/
│   └── B2B_CRM_V8.json          ← n8n workflow (import this)
├── dashboard/
│   ├── index.html               ← CRM dashboard (single file app)
│   ├── config.json.template     ← Config template (copy + fill in)
│   └── nginx.conf               ← nginx server config
├── database/
│   ├── schema.sql               ← Full DB schema + indexes
│   └── seed_templates.sql       ← 12 default email templates
└── docs/
    ├── TESTING.md               ← 8-step testing plan
    ├── DEPLOYMENT.md            ← Step-by-step VPS deployment
    └── CUSTOMISATION.md         ← Per-client customisation guide
```

---

## Quick start (new client deployment)

**Time required: ~30 minutes**

### Prerequisites
- VPS with Docker + Docker Compose installed
- Domain pointed to VPS IP (A records added in DNS)
- This kit extracted on your local machine

### Step 1 — DNS (do this first, before anything else)

Add these A records in your client's DNS panel:

| Type | Name | Value |
|---|---|---|
| A | `n8n` | `YOUR_VPS_IP` |
| A | `dashboard` | `YOUR_VPS_IP` |
| A | `crm` | `YOUR_VPS_IP` |

Wait for DNS to propagate before continuing:
```bash
nslookup n8n.clientdomain.com
# Should return YOUR_VPS_IP
```

### Step 2 — Copy files to VPS

```bash
# From your local machine
scp -r crm-production-kit/ user@YOUR_VPS_IP:/home/user/crm-client/
```

### Step 3 — Configure .env

```bash
ssh user@YOUR_VPS_IP
cd /home/user/crm-client
cp .env.example .env
nano .env
# Fill in all values (see docs/DEPLOYMENT.md for details)
```

### Step 4 — Set up database

```bash
# Start postgres first
docker compose up -d postgres

# Wait for it to be healthy
docker compose ps

# Create schema
docker exec $(docker ps -qf name=postgres) psql -U YOUR_DB_USER -d YOUR_DB_NAME < database/schema.sql

# Seed email templates
docker exec $(docker ps -qf name=postgres) psql -U YOUR_DB_USER -d YOUR_DB_NAME < database/seed_templates.sql
```

### Step 5 — Configure dashboard

```bash
cp dashboard/config.json.template dashboard/config.json
nano dashboard/config.json
# Fill in client name, colors, webhook URLs
```

### Step 6 — Set up password for CRM dashboard

```bash
sudo apt-get install -y apache2-utils
htpasswd -c dashboard/.htpasswd admin
# Enter client's password when prompted
chmod 644 dashboard/.htpasswd
```

### Step 7 — Start all services

```bash
docker compose up -d
```

### Step 8 — Import n8n workflow

1. Open `https://n8n.clientdomain.com`
2. Log in → top right menu → Import from file
3. Upload `workflow/B2B_CRM_V8.json`
4. Update the base URL in `Build_Email` node:
   - Change `https://automation.theworkflowengineer.ovh/webhook` 
   - To `https://n8n.clientdomain.com/webhook`
5. Reconnect credentials (Postgres, SMTP, Slack)
6. Activate the workflow

### Step 9 — Test

Follow the testing plan in `docs/TESTING.md`

---

## Architecture overview

```
Internet
    ↓
Traefik (SSL termination, routing)
    ├── n8n.domain.com          → n8n container (port 5678)
    ├── dashboard.domain.com    → Metabase container (port 3000)
    └── crm.domain.com          → nginx container (port 80)

Internal (backend network only)
    ├── Postgres                → stores everything
    ├── Qdrant                  → vector DB (optional AI features)
    └── Backup                  → daily pg_dump
```

---

## Per-client file checklist

| File | What to change |
|---|---|
| `.env` | All values — domain, passwords, keys |
| `dashboard/config.json` | Client name, color, webhook URLs, Metabase URL |
| `dashboard/.htpasswd` | Client's dashboard password |
| `docker-compose.yml` | Domain names in Traefik labels |
| `workflow/B2B_CRM_V8.json` | Base URL, SMTP sender email, Slack channel, sales rep emails |

---

## Support contacts

- n8n docs: https://docs.n8n.io
- Traefik docs: https://doc.traefik.io/traefik
- Metabase docs: https://www.metabase.com/docs
