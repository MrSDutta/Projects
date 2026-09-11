# Pre-Billing Mismatch Checker v2 — Setup Guide

**What this does:** Catches pricing mismatches between what your sales team agreed with a customer and what your billing system is about to charge them — before the invoice goes out.

**What's new in v2:**
- Sales can enter agreed pricing directly from the dashboard (no SQL required)
- Billing team can enter draft invoices from the dashboard too
- Remarks field on everything — sales notes why that price, reviewers note why they overrode
- Webhook endpoints so your CRM and billing tools can push data in automatically
- Full webhook log for debugging incoming payloads
- Pricing records tab so anyone can see what's on file

**What's in the box:**
- `supabase_schema_v2.sql` — Database tables, comparison logic, sample data
- `n8n_workflow_v2.json` — Automation workflow with webhook endpoints
- `mismatch-dashboard-v2.jsx` — Dashboard with input forms, review table, pricing log
- This guide

---

## Step 1: Set Up Supabase (5 minutes)

1. Go to [supabase.com](https://supabase.com) and create a free project
2. Open the **SQL Editor** in your Supabase dashboard
3. Paste the entire contents of `supabase_schema_v2.sql` and click **Run**
4. Note your **Project URL** and **anon key** from Settings → API

**Verify it worked:** Table Editor should show 6 tables: `client_configs`, `agreed_pricing`, `draft_invoices`, `mismatch_log`, `run_log`, `webhook_log`.

**Important — Row Level Security:** For the dashboard to write data (pricing entries, invoice entries, status updates), you need to either disable RLS on these tables or add policies. Quickest for testing:
- Go to each table → Authentication → Disable RLS (you can tighten this later with proper policies)

---

## Step 2: Import the n8n Workflow (5 minutes)

1. Go to [n8n.io](https://n8n.io) (cloud or self-hosted)
2. **Add Workflow** → **Import from File** → select `n8n_workflow_v2.json`
3. Configure your Supabase connection on any Postgres node:
   - Host: `db.YOUR_PROJECT_ID.supabase.co`
   - Port: `5432` · Database: `postgres` · User: `postgres`
   - Password: your Supabase database password
4. Click **Activate**

The workflow now has **three entry points**:

| Entry point | What it does | When it fires |
|-------------|--------------|---------------|
| **Webhook: Invoice Received** | Stores a draft invoice and triggers comparison | When your billing system sends an invoice payload |
| **Webhook: Pricing Update** | Stores an agreed pricing record | When your CRM sends a deal-close payload |
| **Scheduled Check (Hourly)** | Runs the comparison on any pending invoices | Every hour, catches manually entered data |

**Get your webhook URLs:** After activating, click each webhook node → copy the Production URL. These are what you'll point your billing/CRM integrations at.

---

## Step 3: Deploy the Dashboard (10 minutes)

1. Create a new Vite or Next.js project (or fork the provided template)
2. Drop `mismatch-dashboard-v2.jsx` into your components
3. Update lines 3-4 with your Supabase URL and anon key
4. Update line 5 with your config ID (use the demo one or create your own)
5. Deploy to Vercel: `vercel deploy`

The dashboard has **four tabs:**

| Tab | Who uses it | What it does |
|-----|-------------|--------------|
| **Review Mismatches** | Finance / Controller | See flagged items, override or request revision, add review notes |
| **Enter Agreed Pricing** | Sales team | After a negotiation, enter the customer name, product, agreed price, and remarks |
| **Enter Draft Invoice** | Billing team (or automated via webhook) | Enter an invoice line item to be checked |
| **Pricing Records** | Anyone | View all agreed pricing currently on file |

---

## Step 4: How Data Gets In

Data enters the system through **three channels** — use whichever fits your business:

### Channel 1: Dashboard forms (simplest, no integration needed)
- Sales enters agreed pricing via the "Enter Agreed Pricing" tab after every deal
- Billing enters draft invoices via the "Enter Draft Invoice" tab before sending
- Works immediately, no setup required beyond Step 3

### Channel 2: Webhooks (automated, for businesses with existing tools)
Send a POST request to the webhook URLs from Step 2.

**Invoice webhook payload:**
```json
{
  "config_id": "YOUR_CONFIG_ID",
  "invoice_id": "INV-2024-006",
  "account_name": "Acme Corp",
  "line_item": "Platform License",
  "billed_unit_price": 50.00,
  "quantity": 10,
  "remarks": "Monthly recurring"
}
```

**Pricing webhook payload:**
```json
{
  "config_id": "YOUR_CONFIG_ID",
  "account_name": "Acme Corp",
  "line_item": "Platform License",
  "agreed_unit_price": 42.00,
  "source_reference": "HubSpot Deal #1234",
  "remarks": "Volume discount, 12-month lock",
  "entered_by": "Raj Mehta"
}
```

**How to connect common tools:**

| Tool | Trigger | How |
|------|---------|-----|
| **Stripe** | `invoice.created` webhook | Point Stripe's webhook at your Invoice webhook URL. Map `line_items` to the expected payload shape via an n8n Function node. |
| **QuickBooks** | Invoice creation | Use n8n's QuickBooks node on a schedule, or QuickBooks webhooks if available. |
| **HubSpot** | Deal stage = Closed-Won | Use HubSpot workflow to POST deal pricing to your Pricing webhook URL. |
| **Salesforce** | Opportunity closed | Use Salesforce Flow or Process Builder to POST to your Pricing webhook URL. |
| **Google Sheets** | Row added to pricing sheet | Use n8n's Google Sheets trigger → HTTP Request node to POST to the Pricing webhook. |

### Channel 3: CSV import via Supabase
- Go to Supabase Table Editor → `agreed_pricing` or `draft_invoices`
- Click Import → upload a CSV matching the column structure
- Good for initial migration of existing pricing data

---

## Step 5: Update Your Config

```sql
UPDATE client_configs SET
  business_name = 'Your Company Name',
  mismatch_tolerance = 0.01,
  alert_channel = 'slack',
  alert_destination = 'https://hooks.slack.com/your-actual-webhook'
WHERE id = 'YOUR_CONFIG_ID';
```

---

## How It Works Day-to-Day

**Sales closes a deal:**
1. Sales opens the dashboard → "Enter Agreed Pricing" tab
2. Enters account name, product, agreed price, their name, and a remark explaining the price
3. This is now the source of truth for that customer + product combination

**Invoice goes out:**
1. Draft invoice enters the system (via dashboard form, webhook, or CSV)
2. The hourly check (or immediate webhook trigger) runs the comparison
3. Every line item is matched against agreed pricing

**Three outcomes:**
- **Clean** — prices match, invoice is good to send
- **Flagged** — prices don't match, invoice is paused, Slack/email alert fires
- **Unmatched** — no agreed pricing on file for this account + item (data gap)

**Finance reviews:**
1. Opens dashboard → "Review Mismatches" tab
2. Sees the deviation, the sales remarks explaining the original price, and the source reference
3. Adds their own review note and clicks "Override & Release" or "Request Revision"
4. Everything is logged — who, when, why

---

## The Remarks Trail

Every step captures context:

| Stage | Who writes | What they write | Where it shows |
|-------|-----------|-----------------|----------------|
| Agreed pricing entry | Sales rep | Why this price was agreed, what conditions apply | Pricing Records tab, Slack alert |
| Draft invoice entry | Billing team | Any notes about the invoice | Review table |
| Mismatch review | Finance reviewer | Why they overrode or sent back | Mismatch log (audit trail) |

This trail is the difference between "something was flagged" and "we know exactly what happened and why at every step."

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Dashboard forms don't save | Check that RLS is disabled on the tables, or add INSERT policies for the anon role |
| Webhooks return 404 | Make sure the n8n workflow is activated (toggle in top right) |
| Webhook payloads aren't showing up | Check `webhook_log` table in Supabase — raw payloads are logged there |
| Everything shows as "unmatched" | Account names and line items must match between agreed pricing and draft invoices (case-insensitive, but spelling must match) |
| Hourly check runs but finds 0 | Check that draft invoices have `status = 'pending_review'` |

---

## Support

This is a VikFlow product. If you purchased the Setup or Retention tier, reach out to souvik@vikflow.com for configuration help.
