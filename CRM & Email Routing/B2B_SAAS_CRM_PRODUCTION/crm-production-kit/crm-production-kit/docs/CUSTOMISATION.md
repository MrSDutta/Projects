# Customisation guide
### What to change for each new client

---

## Overview

This CRM is config-driven. Most client customisations require changing just a few files — no code changes needed.

---

## 1. Branding (dashboard/config.json)

```json
{
  "client": {
    "name": "Client Name CRM",
    "logo_letter": "C",
    "primary_color": "#3b82f6"
  }
}
```

| Field | What it does |
|---|---|
| `name` | Shown in browser tab and sidebar |
| `logo_letter` | Letter shown in the logo mark (top left) |
| `primary_color` | Accent color throughout the dashboard |

After changing: `docker compose restart crm-dashboard`

---

## 2. Webhook URLs (dashboard/config.json)

```json
{
  "integrations": {
    "n8n_webhook_lead_capture": "https://n8n.clientdomain.com/webhook/7300c6e1-...",
    "n8n_webhook_live_feed": "https://n8n.clientdomain.com/webhook/live-feed",
    "n8n_webhook_templates": "https://n8n.clientdomain.com/webhook/update-email-templates",
    "metabase_url": "https://dashboard.clientdomain.com/public/dashboard/xxxxx"
  }
}
```

The lead capture webhook ID (`7300c6e1-...`) never changes — it's hardcoded in the workflow.

---

## 3. Feature toggles (dashboard/config.json)

Hide pages you don't want the client to see:

```json
{
  "features": {
    "template_editor": true,
    "csv_importer": true,
    "live_feed": true,
    "analytics": true
  }
}
```

Set any to `false` to hide that page from the navigation.

---

## 4. Sales rep assignment (n8n workflow)

Open these two nodes in n8n and update the CASE statements:

**Create_Leads node:**
```sql
CASE
  WHEN '{{ $json.segment }}' = 'Enterprise'  THEN 'enterprise@clientdomain.com'
  WHEN '{{ $json.segment }}' = 'Mid-Market'  THEN 'midmarket@clientdomain.com'
  WHEN '{{ $json.segment }}' = 'SMB'         THEN 'smb@clientdomain.com'
  ELSE 'default@clientdomain.com'
END
```

**Update_Leads node:** Same CASE statement — keep both in sync.

---

## 5. Email sender (n8n workflow)

Change `fromEmail` in all email send nodes:
- `Enterprise_Send_Email`
- `Mid-Market_Send_Email`
- `SMB_Send_Email`
- `Send Email (SMTP)`

Also update the SMTP credential to use the client's email account.

---

## 6. Email templates (CRM dashboard)

The client can edit templates themselves through the CRM dashboard at `https://crm.clientdomain.com` → Email templates.

Or you can update directly in Postgres:
```sql
UPDATE crm.email_templates
SET subject = 'New subject', html = '<p>New content</p>'
WHERE segment = 'Enterprise' AND stage = 1;
```

---

## 7. Company enrichment (n8n workflow)

The `Company_Enrichment & Segmentation` node has a hardcoded `companyDB` for known domains. Add client-specific companies:

```js
const companyDB = {
  'clientcompany.com': {
    company: 'Client Company Name',
    industry: 'SaaS',
    company_size: 500
  },
  // add more known domains here
};
```

---

## 8. Segmentation thresholds (n8n workflow)

Default thresholds in `Company_Enrichment & Segmentation`:
- `company_size > 50` → Enterprise
- `company_size >= 10` → Mid-Market
- else → SMB

Change these numbers based on client's definition of segments.

---

## 9. Lead scoring weights (n8n workflow)

Default scores in `Update_Score` node:
```sql
WHEN 'email_opened'         THEN 5
WHEN 'link_clicked'         THEN 10
WHEN 'pricing_page_visited' THEN 20
WHEN 'demo_requested'       THEN 25
```

Adjust based on what the client values most.

---

## 10. Hot lead threshold (n8n workflow)

Default: `lead_score >= 50` triggers Hot status + Slack alert.

Change in the `If` node condition:
- Left value: `={{$json.lead_score}}`
- Operator: `greater than or equal`
- Right value: `50` ← change this

---

## 11. Email sequence timing (n8n workflow)

**First email delay** (Update_Nurturing node):
```sql
next_email_scheduled = NOW() + INTERVAL '3 days'
```

**Between sequence emails** (Build_Email node):
```js
const intervalDays = { 1: 3, 2: 5, 3: 7 };
```

**Cron run time** (Schedule Trigger node):
- Currently: 10:00 AM
- Change `triggerAtHour` value

---

## 12. Slack channel (n8n workflow)

Update the channel ID in these nodes:
- `Send a message` (hot lead alert)
- `Slack_Resubmit_Alert` (nurturing resubmit)
- `Slack_Resubmit_Alert(Hot)` (hot lead resubmit)

Find channel ID: In Slack, right-click channel → View channel details → scroll to bottom.

---

## Quick reference — files per customisation

| What to change | File/Location |
|---|---|
| Client name, color, logo | `dashboard/config.json` |
| Webhook URLs | `dashboard/config.json` |
| Hide/show pages | `dashboard/config.json` |
| Dashboard password | `dashboard/.htpasswd` (regenerate with htpasswd) |
| Sales rep emails | n8n → Create_Leads + Update_Leads nodes |
| SMTP sender email | n8n → all email send nodes + SMTP credential |
| Email templates content | CRM dashboard → Email templates page |
| Segmentation thresholds | n8n → Company_Enrichment node |
| Lead scoring weights | n8n → Update_Score node |
| Hot lead threshold | n8n → If node |
| Sequence timing | n8n → Update_Nurturing + Build_Email nodes |
| Slack channel | n8n → all Slack nodes |
| Metabase dashboard URL | `dashboard/config.json` |
