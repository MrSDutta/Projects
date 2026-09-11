-- B2B CRM Database Schema
-- Run this once on a fresh Postgres instance
-- Database: your n8n database (default: n8n)

-- ── Create CRM schema ─────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS crm;

-- ── Leads table ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS crm.leads (
  id                   BIGINT PRIMARY KEY,
  name                 TEXT,
  email                TEXT,
  company              TEXT,
  domain               TEXT,
  company_size         INTEGER DEFAULT 0,
  industry             TEXT,
  segment              TEXT,
  linkedin             TEXT,
  message              TEXT,
  source               TEXT,
  referred_by          TEXT,
  ip_address           TEXT,
  user_agent           TEXT,
  is_business_email    BOOLEAN DEFAULT TRUE,
  lead_score           INTEGER DEFAULT 0,
  email_sent           BOOLEAN DEFAULT FALSE,
  status               TEXT DEFAULT 'New',
  email_opened         BOOLEAN DEFAULT FALSE,
  link_clicked         BOOLEAN DEFAULT FALSE,
  assigned_to          TEXT,
  notes                TEXT,
  last_activity        TIMESTAMP WITHOUT TIME ZONE,
  created_at           TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  email_sequence_stage INTEGER DEFAULT 0,
  last_email_sent_at   TIMESTAMP WITHOUT TIME ZONE,
  next_email_scheduled TIMESTAMP WITHOUT TIME ZONE,
  sequence_active      BOOLEAN DEFAULT FALSE
);

-- ── Unique constraint on email ────────────────────────────
ALTER TABLE crm.leads
  ADD CONSTRAINT IF NOT EXISTS leads_email_unique UNIQUE (email);

-- ── Indexes for performance ───────────────────────────────
CREATE INDEX IF NOT EXISTS idx_leads_email
  ON crm.leads(email);

CREATE INDEX IF NOT EXISTS idx_leads_status
  ON crm.leads(status);

CREATE INDEX IF NOT EXISTS idx_leads_segment
  ON crm.leads(segment);

CREATE INDEX IF NOT EXISTS idx_leads_score
  ON crm.leads(lead_score);

CREATE INDEX IF NOT EXISTS idx_leads_sequence
  ON crm.leads(sequence_active, next_email_scheduled);

CREATE INDEX IF NOT EXISTS idx_leads_last_activity
  ON crm.leads(last_activity DESC);

-- ── Email templates table ─────────────────────────────────
CREATE TABLE IF NOT EXISTS crm.email_templates (
  segment    TEXT NOT NULL,
  stage      INTEGER NOT NULL,
  subject    TEXT NOT NULL,
  html       TEXT NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  PRIMARY KEY (segment, stage)
);

-- ── Verify ────────────────────────────────────────────────
SELECT
  table_schema,
  table_name,
  (SELECT COUNT(*) FROM information_schema.columns c
   WHERE c.table_schema = t.table_schema
   AND c.table_name = t.table_name) AS column_count
FROM information_schema.tables t
WHERE table_schema = 'crm'
ORDER BY table_name;
