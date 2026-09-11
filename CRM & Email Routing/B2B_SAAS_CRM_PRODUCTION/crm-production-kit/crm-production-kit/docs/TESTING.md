# Testing plan
### 8 tests to run before going live or demoing to a client

Run in order. Each test builds on the previous.

---

## Before you start

Make sure:
- All containers are running: `docker ps`
- Workflow is activated in n8n
- You have a real email address you can check

---

## Test 1 — New business lead (critical)

**What it tests:** Full lead capture pipeline — webhook → normalise → enrich → insert → email send → sequence start

**How to run:**
```bash
curl -X POST https://n8n.DOMAIN/webhook/7300c6e1-b534-41af-8248-dac2d60be9ee \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User","email":"YOUR_REAL_EMAIL","source":"4wf5673","message":"Testing"}'
```

**Check database:**
```bash
docker exec $(docker ps -qf name=postgres) psql -U DB_USER -d DB_NAME -c \
  "SELECT name, email, segment, status, sequence_active, next_email_scheduled, assigned_to FROM crm.leads WHERE email='YOUR_REAL_EMAIL';"
```

**Expected results:**
- Response: `{"message":"Workflow was started"}`
- Lead in DB with correct segment (Enterprise/Mid-Market/SMB)
- `status = Nurturing`
- `sequence_active = true`
- `next_email_scheduled` = 3 days from now
- `assigned_to` populated with sales rep email
- Intro email received in inbox within 60 seconds

---

## Test 2 — Public domain lead (critical)

**What it tests:** Gmail/Yahoo emails go to newsletter path, not CRM pipeline

**How to run:**
```bash
curl -X POST https://n8n.DOMAIN/webhook/7300c6e1-b534-41af-8248-dac2d60be9ee \
  -H "Content-Type: application/json" \
  -d '{"name":"Gmail User","email":"testuser123@gmail.com","source":"4wf5673","message":"Test"}'
```

**Expected results:**
- Lead in DB with `is_business_email = false`
- `status = Newsletter`
- `sequence_active = false`
- No intro email sent

---

## Test 3 — Duplicate lead (critical)

**What it tests:** Same email submitted twice does not re-send intro email or create duplicate

**How to run:** Send the same curl from Test 1 again

**Expected results:**
- No duplicate row in DB
- `last_activity` timestamp updated
- No second intro email sent
- n8n execution shows update path (Route_By_Status)

---

## Test 4 — Email open tracking (critical)

**What it tests:** Open pixel fires, score increments, email_opened flag set

**How to run:** Open the intro email received in Test 1

**Check:**
```bash
docker exec $(docker ps -qf name=postgres) psql -U DB_USER -d DB_NAME -c \
  "SELECT lead_score, email_opened FROM crm.leads WHERE email='YOUR_REAL_EMAIL';"
```

**Expected results:**
- `lead_score = 5` (was 0)
- `email_opened = true`

---

## Test 5 — Link click tracking + redirect (critical)

**What it tests:** Tracked links redirect correctly AND update score

**How to run:** Click any link in the intro email

**Expected results:**
- Browser lands on target page (not blank n8n screen)
- `lead_score = 15` (5 from open + 10 from click)
- `link_clicked = true`

---

## Test 6 — Hot lead Slack alert (critical)

**What it tests:** Lead score threshold triggers status change and Slack notification

**How to run:**
```bash
# Set score to 45 (one click will push it to 55, over the 50 threshold)
docker exec $(docker ps -qf name=postgres) psql -U DB_USER -d DB_NAME -c \
  "UPDATE crm.leads SET lead_score=45 WHERE email='YOUR_REAL_EMAIL';"

# Then click a link in the email to trigger +10
```

**Expected results:**
- `status = Hot`
- Slack message received in your channel
- Message contains name, company, email, segment, score

---

## Test 7 — CSV lead importer (important)

**What it tests:** Bulk lead upload from CSV file

**How to run:**
1. Open `https://crm.DOMAIN`
2. Login with admin credentials
3. Go to Lead importer page
4. Upload `test_leads.csv` (8 rows)
5. Verify column mapping
6. Click Import

**Check:**
```bash
docker exec $(docker ps -qf name=postgres) psql -U DB_USER -d DB_NAME -c \
  "SELECT name, email, segment, status FROM crm.leads ORDER BY created_at DESC LIMIT 10;"
```

**Expected results:**
- 8 new leads in database
- Correct segments assigned
- No duplicates
- Each lead gets `status = New`

---

## Test 8 — Email template editor (important)

**What it tests:** Template changes push to Postgres and affect future sequence emails

**How to run:**
1. Open `https://crm.DOMAIN` → Email templates
2. Edit Enterprise Stage 1 subject — add "TEST:" at the start
3. Click Push to n8n
4. Check Postgres:

```bash
docker exec $(docker ps -qf name=postgres) psql -U DB_USER -d DB_NAME -c \
  "SELECT subject FROM crm.email_templates WHERE segment='Enterprise' AND stage=1;"
```

5. Confirm subject starts with "TEST:"
6. Revert the change and push again

**Expected results:**
- Template updated in DB immediately
- Next sequence email for Enterprise leads uses new template

---

## Sign-off checklist

Before handing over to client:

- [ ] Test 1 passed — new lead captured, email received
- [ ] Test 2 passed — gmail leads go to newsletter
- [ ] Test 3 passed — no duplicate emails
- [ ] Test 4 passed — email open tracked
- [ ] Test 5 passed — link click redirects correctly
- [ ] Test 6 passed — Slack hot lead alert fires
- [ ] Test 7 passed — CSV import works
- [ ] Test 8 passed — template editor works
- [ ] All email templates have real copy (no "Team XYZ" or "example.com")
- [ ] Sales rep emails updated in workflow
- [ ] Client's Metabase dashboard built and embedded
- [ ] CRM dashboard password set for client
