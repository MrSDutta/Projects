# Deployment guide
### Step-by-step instructions for a production VPS deployment

---

## VPS requirements

- OS: Ubuntu 22.04 or Debian 11/12
- RAM: 4GB minimum (8GB recommended)
- Storage: 40GB minimum
- Docker + Docker Compose installed

---

## 1. Initial VPS setup

```bash
# SSH into VPS
ssh user@YOUR_VPS_IP

# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker

# Verify
docker --version
docker compose version
```

---

## 2. Create project folder

```bash
mkdir -p /home/user/crm-client
cd /home/user/crm-client
```

---

## 3. Create .env file

```bash
nano .env
```

Paste and fill in all values:

```env
# ── Domain ────────────────────────────────────────────────
DOMAIN_NAME=clientdomain.com
SUBDOMAIN_1=n8n
SUBDOMAIN_2=dashboard
SUBDOMAIN_3=crm
SSL_EMAIL=client@email.com

# ── Postgres ───────────────────────────────────────────────
POSTGRES_USER=crm_user
POSTGRES_PASSWORD=GENERATE_STRONG_PASSWORD
POSTGRES_DB=n8n

# ── n8n ───────────────────────────────────────────────────
# Generate with: openssl rand -hex 32
N8N_ENCRYPTION_KEY=GENERATE_32_CHAR_RANDOM
N8N_USER_MANAGEMENT_JWT_SECRET=GENERATE_32_CHAR_RANDOM
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin@clientdomain.com
N8N_BASIC_AUTH_PASSWORD=GENERATE_STRONG_PASSWORD

# ── Timezone ──────────────────────────────────────────────
GENERIC_TIMEZONE=Asia/Kolkata
TZ=Asia/Kolkata

# ── SSL ───────────────────────────────────────────────────
SSL_EMAIL=client@email.com
```

Generate secure values:
```bash
# Generate random keys
openssl rand -hex 32   # use for N8N_ENCRYPTION_KEY
openssl rand -hex 32   # use for N8N_USER_MANAGEMENT_JWT_SECRET
openssl rand -base64 16  # use for passwords
```

---

## 4. Copy docker-compose.yml

Use the docker-compose.yml from this kit. Key things to verify:
- All `SUBDOMAIN_X.DOMAIN_NAME` references match your .env
- Metabase service has correct `MB_DB_*` values
- `crm-dashboard` service has all 4 volume mounts including `.htpasswd`

---

## 5. Database setup

```bash
# Start only postgres first
docker compose up -d postgres

# Wait until healthy (check with)
docker compose ps
# Should show: n8n-postgres-1  Up X seconds (healthy)

# Run schema
docker exec -i $(docker ps -qf name=postgres) psql -U $POSTGRES_USER -d $POSTGRES_DB < database/schema.sql

# Run seed templates
docker exec -i $(docker ps -qf name=postgres) psql -U $POSTGRES_USER -d $POSTGRES_DB < database/seed_templates.sql

# Verify tables exist
docker exec $(docker ps -qf name=postgres) psql -U $POSTGRES_USER -d $POSTGRES_DB -c "\dt crm.*"
# Should show: crm.leads and crm.email_templates
```

---

## 6. Dashboard setup

```bash
# Copy and edit config
cp dashboard/config.json.template dashboard/config.json
nano dashboard/config.json

# Set up password
sudo apt-get install -y apache2-utils
htpasswd -c dashboard/.htpasswd admin
chmod 644 dashboard/.htpasswd
```

---

## 7. Start all services

```bash
docker compose up -d

# Verify all running
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
```

Expected output:
```
NAMES                  STATUS           IMAGE
n8n-crm-dashboard-1   Up X seconds     nginx:alpine
n8n-metabase-1        Up X seconds     metabase/metabase:latest
n8n                   Up X seconds     n8nio/n8n:latest
n8n-postgres-1        Up X seconds     postgres:16-alpine
n8n-traefik-1         Up X seconds     traefik:latest
qdrant                Up X seconds     qdrant/qdrant:latest
n8n-backup-1          Up X seconds     postgres:16-alpine
```

---

## 8. Wait for SSL certs

Traefik automatically requests Let's Encrypt certs. Wait 2-3 minutes then verify:

```bash
docker exec $(docker ps -qf name=traefik) cat /letsencrypt/acme.json | python3 -c "
import json,sys
d=json.load(sys.stdin)
for resolver,data in d.items():
    for c in (data.get('Certificates') or []):
        print(c.get('domain',{}).get('main','?'))
"
```

All 3 subdomains should appear.

---

## 9. Import n8n workflow

1. Open `https://n8n.clientdomain.com`
2. Create admin account on first login
3. Top right menu (≡) → **Import from file**
4. Upload `workflow/B2B_CRM_V8.json`
5. Open `Build_Email` node → update base URL:
   ```js
   const baseUrl = 'https://n8n.clientdomain.com/webhook';
   ```
6. Open `Create_Leads` node → update sales rep emails:
   ```sql
   WHEN 'Enterprise' THEN 'enterprise-rep@clientdomain.com'
   WHEN 'Mid-Market' THEN 'midmarket-rep@clientdomain.com'
   WHEN 'SMB'        THEN 'smb-rep@clientdomain.com'
   ```
7. Open `Update_Leads` node → same rep emails
8. Reconnect credentials:
   - Postgres: host=`postgres`, db=`n8n`, user/pass from .env
   - SMTP: client's email sending credentials
   - Slack: client's Slack workspace
9. Click **Activate** toggle

---

## 10. Set up Metabase

1. Open `https://dashboard.clientdomain.com`
2. Complete first-time setup wizard
3. When asked to connect a database:
   - Type: PostgreSQL
   - Host: `postgres`
   - Port: `5432`
   - Database: `n8n`
   - Username/Password: from .env
   - Schema: `crm`
4. Build dashboards using `crm.leads` and `crm.email_templates` tables
5. Enable public sharing: Admin → Settings → Embedding → Enable guest embeds
6. Share your dashboard → get public link
7. Update `dashboard/config.json` with the public link URL
8. Restart dashboard: `docker compose restart crm-dashboard`

---

## 11. Final verification

```bash
# All containers running
docker ps

# Lead table ready
docker exec $(docker ps -qf name=postgres) psql -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT COUNT(*) FROM crm.leads;"

# Templates seeded
docker exec $(docker ps -qf name=postgres) psql -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT segment, stage, subject FROM crm.email_templates ORDER BY segment, stage;"

# Test lead capture
curl -X POST https://n8n.clientdomain.com/webhook/7300c6e1-b534-41af-8248-dac2d60be9ee \
  -H "Content-Type: application/json" \
  -d '{"name":"Test","email":"YOUR_EMAIL","source":"4wf5673","message":"Test"}'
```

---

## Common issues

| Problem | Cause | Fix |
|---|---|---|
| SSL cert not issued | DNS not propagated yet | Wait 5 min, verify with nslookup |
| SSL cert not issued | Let's Encrypt rate limit | Wait 1 hour, restart traefik |
| Metabase won't start | `metabase` DB doesn't exist | Run schema.sql which creates it |
| n8n credential error | Wrong host (localhost vs postgres) | Use `postgres` as hostname, not localhost |
| 403 on CRM dashboard | .htpasswd not mounted | Check docker-compose volumes, recreate container |
| Workflow not firing | Workflow not activated | Click Activate toggle in n8n |
| Email not sending | SMTP credentials wrong | Test SMTP in n8n credentials page |
