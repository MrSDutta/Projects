# Pre-Billing Mismatch Checker — Setup Guide

**What this does:** Before your invoice goes out, this tool checks every line item against what was actually agreed with the customer. Mismatches get caught and flagged before the customer ever sees a wrong number.

**What's in the box:**
- `supabase_schema.sql` — Database tables + comparison logic
- `n8n_workflow.json` — Automation workflow (importable into n8n)
- `mismatch-dashboard.jsx` — Review dashboard (deployable on Vercel)
- This guide

## Step 1: Set Up Supabase (5 minutes)

1. Go to [supabase.com](https://supabase.com) and create a free project
2. Open the **SQL Editor** in your Supabase dashboard
3. Paste the entire contents of `supabase_schema.sql` and click **Run**
4. This creates all tables, the comparison function, and sample demo data
5. Note your **Project URL** and **anon key** from Settings → API — you'll need both

**Verify it worked:** Go to Table Editor → you should see 5 tables: `client_configs`, `agreed_pricing`, `draft_invoices`, `mismatch_log`, `run_log`. The `agreed_pricing` and `draft_invoices` tables should have sample data pre-loaded.

## Step 2: Import the n8n Workflow (5 minutes)

1. Go to [n8n.io](https://n8n.io) (cloud or self-hosted)
2. Click **Add Workflow** → **Import from File** → select `n8n_workflow.json`
3. Open the workflow — you'll see nodes connected in sequence
4. **Configure your Supabase connection:**
   - Click any Postgres node → Credentials → Create New
   - Host: `db.YOUR_PROJECT_ID.supabase.co`
   - Port: `5432`
   - Database: `postgres`
   - User: `postgres`
   - Password: your Supabase database password
5. **Optional — Slack alerts:** Click the Slack Alert node → add your Slack credentials and set the channel name
6. Click **Activate** (top right toggle)

**Test it:** Click "Execute Workflow" manually. You should see the sample data flow through — 4 clean, 4 flagged, 1 unmatched.


## Step 3: Deploy the Dashboard (10 minutes)

### Option A: Vercel (recommended, free)

1. Create a new Next.js or Vite project locally, or fork the provided template
2. Drop `mismatch-dashboard.jsx` into your components
3. Open the file and replace `YOUR_PROJECT` and `YOUR_ANON_KEY` with your actual Supabase values (lines 3-4)
4. Deploy to Vercel (`vercel deploy`)

### Option B: Retool (alternative, also free tier)

1. Create a Retool account
2. Create a new app → add a Supabase resource with your credentials
3. Build a table component querying `mismatch_log` ordered by `created_at desc`
4. Add two buttons per row calling the `release_invoice` and `revise_invoice` database functions

## Step 4: Load Your Real Data

Replace the sample data with your actual business data:

### Agreed Pricing (what was promised)
For each customer + line item, insert a row into `agreed_pricing`:

```sql
INSERT INTO agreed_pricing (config_id, account_name, line_item, agreed_unit_price, source_reference)
VALUES (
  'YOUR_CONFIG_ID',
  'Customer Name',
  'Product or Service Name',
  42.00,
  'Where this price was agreed (e.g., Salesforce Opp #1234)'
);
```

**Where this data comes from:** your CRM deal records, signed contracts, email confirmations — wherever the real negotiated price lives today.

### Draft Invoices (what billing is about to send)
For each invoice line item, insert a row into `draft_invoices`:

```sql
INSERT INTO draft_invoices (config_id, invoice_id, account_name, line_item, billed_unit_price, quantity)
VALUES (
  'YOUR_CONFIG_ID',
  'INV-2024-001',
  'Customer Name',
  'Product or Service Name',
  50.00,
  10
);
```

**Where this data comes from:** your billing system (Stripe, QuickBooks, Zoho). Ideally, automate this via webhook or API sync — see Step 5.

## Step 5: Connect Your Live Systems (optional, makes it fully automated)

### Billing Source → Draft Invoices table

| System | How to connect |
|--------|----------------|
| **Stripe** | Use Stripe's `invoice.created` webhook to push draft invoice line items into the `draft_invoices` table via an n8n Webhook node |
| **QuickBooks** | Use the QuickBooks API `Invoice` endpoint, polled hourly via the n8n Schedule node |
| **Zoho Books** | Use Zoho's webhook on invoice creation, or poll the API |
| **Manual/CSV** | Upload a CSV of draft invoices to Supabase via the Table Editor import |

### Pricing Source → Agreed Pricing table

| System | How to connect |
|--------|----------------|
| **Salesforce** | Query the Opportunity Price Book via Salesforce REST API on a nightly schedule |
| **HubSpot** | Pull deal line items via the HubSpot Deals API |
| **Google Sheets** | Use the Google Sheets node in n8n to sync a pricing sheet nightly |
| **Manual** | Enter directly into Supabase Table Editor or via the dashboard |

## Step 6: Update Your Config

Edit the `client_configs` row to match your business:

```sql
UPDATE client_configs SET
  business_name = 'Your Company Name',
  mismatch_tolerance = 0.01,          -- flag anything off by more than $0.01
  alert_channel = 'slack',            -- or 'email'
  alert_destination = 'https://hooks.slack.com/your-actual-webhook'
WHERE id = 'YOUR_CONFIG_ID';
```

**Tolerance:** Set this to whatever makes sense for your billing. `0.01` catches everything. `1.00` ignores sub-dollar rounding. `0` flags even exact-penny differences.

## How It Works Day-to-Day

1. Draft invoices land in the `draft_invoices` table (manually or via automation)
2. The n8n workflow runs (hourly, or on webhook trigger) and compares each line against `agreed_pricing`
3. Clean invoices get marked `clean` — send them
4. Flagged invoices appear on the dashboard with the exact deviation
5. A reviewer enters their name and clicks **Override & Release** (send it anyway) or **Request Revision** (fix it first)
6. Every action is logged with who did it and when — full audit trail

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Workflow runs but finds 0 invoices | Check that `draft_invoices` rows have `status = 'pending_review'` |
| Everything shows as "unmatched" | Account names and line items must match between `agreed_pricing` and `draft_invoices` (case-insensitive, but spelling must match) |
| Dashboard shows no data | Verify your Supabase URL and anon key are correct in the dashboard code |
| Slack alerts not firing | Check Slack credentials in n8n; verify the channel name exists |

## Support

This is a VikFlow product. If you purchased the Setup or Retention tier, reach out to souvik@vikflow.com for configuration help.
