-- ============================================
-- VikFlow — Pre-Billing Mismatch Checker v3
-- CLEAN INSTALL: Drops all v2 tables first
-- Removed: client_configs (not needed for single-business use)
-- ============================================

-- ── Drop old tables (order matters — foreign keys first) ──
DROP FUNCTION IF EXISTS run_mismatch_check(UUID) CASCADE;
DROP FUNCTION IF EXISTS release_invoice(UUID, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS revise_invoice(UUID, TEXT, TEXT) CASCADE;
DROP TABLE IF EXISTS webhook_log CASCADE;
DROP TABLE IF EXISTS run_log CASCADE;
DROP TABLE IF EXISTS mismatch_log CASCADE;
DROP TABLE IF EXISTS draft_invoices CASCADE;
DROP TABLE IF EXISTS agreed_pricing CASCADE;
DROP TABLE IF EXISTS client_configs CASCADE;

-- ============================================
-- 1. Agreed pricing — what sales promised the customer
-- ============================================
CREATE TABLE agreed_pricing (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    account_name TEXT NOT NULL,
    line_item TEXT NOT NULL,
    agreed_unit_price NUMERIC(12,2) NOT NULL,
    currency TEXT DEFAULT 'USD',
    effective_from DATE DEFAULT CURRENT_DATE,
    effective_until DATE,
    source_reference TEXT,
    remarks TEXT,
    entered_by TEXT,
    entry_method TEXT DEFAULT 'manual',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- 2. Draft invoices — what billing is about to send
-- ============================================
CREATE TABLE draft_invoices (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    invoice_id TEXT NOT NULL,
    account_name TEXT NOT NULL,
    line_item TEXT NOT NULL,
    billed_unit_price NUMERIC(12,2) NOT NULL,
    quantity NUMERIC(12,2) DEFAULT 1,
    currency TEXT DEFAULT 'USD',
    invoice_date DATE DEFAULT CURRENT_DATE,
    status TEXT DEFAULT 'pending_review',
    remarks TEXT,
    entry_method TEXT DEFAULT 'manual',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- 3. Mismatch log — every comparison result
-- ============================================
CREATE TABLE mismatch_log (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    draft_invoice_id UUID REFERENCES draft_invoices(id) ON DELETE CASCADE,
    agreed_pricing_id UUID REFERENCES agreed_pricing(id) ON DELETE SET NULL,
    account_name TEXT NOT NULL,
    line_item TEXT NOT NULL,
    agreed_price NUMERIC(12,2),
    billed_price NUMERIC(12,2) NOT NULL,
    deviation NUMERIC(12,2) NOT NULL,
    deviation_pct NUMERIC(6,2),
    match_status TEXT NOT NULL DEFAULT 'flagged',
    reviewed_by TEXT,
    reviewed_at TIMESTAMPTZ,
    review_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- 4. Run log — tracks every execution
-- ============================================
CREATE TABLE run_log (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    run_at TIMESTAMPTZ DEFAULT NOW(),
    total_invoices_checked INTEGER DEFAULT 0,
    clean_count INTEGER DEFAULT 0,
    flagged_count INTEGER DEFAULT 0,
    unmatched_count INTEGER DEFAULT 0,
    run_status TEXT DEFAULT 'success',
    error_message TEXT
);

-- ============================================
-- 5. Webhook log — debugging incoming payloads
-- ============================================
CREATE TABLE webhook_log (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    source TEXT NOT NULL,
    payload JSONB NOT NULL,
    processed BOOLEAN DEFAULT FALSE,
    error_message TEXT,
    received_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- Indexes
-- ============================================
CREATE INDEX idx_agreed_pricing_account ON agreed_pricing(account_name, line_item);
CREATE INDEX idx_draft_invoices_account ON draft_invoices(account_name, line_item);
CREATE INDEX idx_draft_invoices_status ON draft_invoices(status);
CREATE INDEX idx_mismatch_log_status ON mismatch_log(match_status);
CREATE INDEX idx_webhook_log_processed ON webhook_log(processed);

-- ============================================
-- Core comparison function
-- Tolerance is passed in directly (set in n8n workflow)
-- ============================================
CREATE OR REPLACE FUNCTION run_mismatch_check(p_tolerance NUMERIC DEFAULT 0.01)
RETURNS VOID AS $$
DECLARE
    v_total INTEGER := 0;
    v_clean INTEGER := 0;
    v_flagged INTEGER := 0;
    v_unmatched INTEGER := 0;
BEGIN
    -- Insert comparison results into mismatch_log
    INSERT INTO mismatch_log (draft_invoice_id, agreed_pricing_id, account_name, line_item, agreed_price, billed_price, deviation, deviation_pct, match_status)
    SELECT
        di.id,
        ap.id,
        di.account_name,
        di.line_item,
        ap.agreed_unit_price,
        di.billed_unit_price,
        ABS(di.billed_unit_price - COALESCE(ap.agreed_unit_price, 0)),
        CASE
            WHEN ap.agreed_unit_price IS NOT NULL AND ap.agreed_unit_price > 0
            THEN ROUND(ABS(di.billed_unit_price - ap.agreed_unit_price) / ap.agreed_unit_price * 100, 2)
            ELSE NULL
        END,
        CASE
            WHEN ap.id IS NULL THEN 'unmatched'
            WHEN ABS(di.billed_unit_price - ap.agreed_unit_price) <= p_tolerance THEN 'clean'
            ELSE 'flagged'
        END
    FROM draft_invoices di
    LEFT JOIN agreed_pricing ap
        ON LOWER(TRIM(di.account_name)) = LOWER(TRIM(ap.account_name))
        AND LOWER(TRIM(di.line_item)) = LOWER(TRIM(ap.line_item))
        AND (ap.effective_until IS NULL OR ap.effective_until >= di.invoice_date)
    WHERE di.status = 'pending_review';

    -- Update draft invoice statuses
    UPDATE draft_invoices di
    SET status = ml.match_status
    FROM mismatch_log ml
    WHERE ml.draft_invoice_id = di.id
        AND di.status = 'pending_review';

    -- Count results
    SELECT COUNT(*) INTO v_total FROM draft_invoices WHERE status != 'pending_review' AND created_at > NOW() - INTERVAL '1 minute';
    SELECT COUNT(*) INTO v_clean FROM mismatch_log WHERE match_status = 'clean' AND created_at > NOW() - INTERVAL '1 minute';
    SELECT COUNT(*) INTO v_flagged FROM mismatch_log WHERE match_status = 'flagged' AND created_at > NOW() - INTERVAL '1 minute';
    SELECT COUNT(*) INTO v_unmatched FROM mismatch_log WHERE match_status = 'unmatched' AND created_at > NOW() - INTERVAL '1 minute';

    -- Log the run
    INSERT INTO run_log (total_invoices_checked, clean_count, flagged_count, unmatched_count)
    VALUES (v_total, v_clean, v_flagged, v_unmatched);
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- Action functions (called from dashboard)
-- ============================================
CREATE OR REPLACE FUNCTION release_invoice(p_mismatch_id UUID, p_reviewer TEXT, p_notes TEXT DEFAULT NULL)
RETURNS VOID AS $$
BEGIN
    UPDATE mismatch_log
    SET match_status = 'released', reviewed_by = p_reviewer, reviewed_at = NOW(), review_notes = p_notes
    WHERE id = p_mismatch_id;
    UPDATE draft_invoices SET status = 'released'
    WHERE id = (SELECT draft_invoice_id FROM mismatch_log WHERE id = p_mismatch_id);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION revise_invoice(p_mismatch_id UUID, p_reviewer TEXT, p_notes TEXT DEFAULT NULL)
RETURNS VOID AS $$
BEGIN
    UPDATE mismatch_log
    SET match_status = 'revised', reviewed_by = p_reviewer, reviewed_at = NOW(), review_notes = p_notes
    WHERE id = p_mismatch_id;
    UPDATE draft_invoices SET status = 'revised'
    WHERE id = (SELECT draft_invoice_id FROM mismatch_log WHERE id = p_mismatch_id);
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- Sample data (no config_id needed)
-- ============================================
INSERT INTO agreed_pricing (account_name, line_item, agreed_unit_price, source_reference, remarks, entered_by) VALUES
('Acme Corp',        'Platform License',      42.00, 'Salesforce Opp #1001',      'Standard enterprise rate, 12-month lock',           'Raj Mehta'),
('Acme Corp',        'API Add-on',            15.00, 'Salesforce Opp #1001',      'Bundled discount, valid only with Platform License', 'Raj Mehta'),
('Globex Industries', 'Platform License',      38.50, 'Email thread 2024-06-10',   'Volume discount for 20+ seats',                      'Priya Shah'),
('Globex Industries', 'Premium Support',       25.00, 'Contract Amendment #3',     'Reduced from $35 after renewal negotiation',         'Priya Shah'),
('Initech LLC',       'Platform License',      45.00, 'HubSpot Deal #2055',        'Mid-market rate, annual billing',                    'Arjun Nair'),
('Initech LLC',       'Data Storage (per GB)', 0.12,  'HubSpot Deal #2055',        'Committed minimum 500GB',                            'Arjun Nair'),
('Wayne Enterprises', 'Platform License',      50.00, 'Salesforce Opp #3300',      'Premium tier, includes priority SLA',                 'Raj Mehta'),
('Wayne Enterprises', 'Custom Integration',    200.00,'Contract v2 signed 2024-08','One-time setup fee, not recurring',                   'Raj Mehta');

INSERT INTO draft_invoices (invoice_id, account_name, line_item, billed_unit_price, quantity) VALUES
('INV-2024-001', 'Acme Corp',        'Platform License',      42.00, 10),   -- CLEAN
('INV-2024-001', 'Acme Corp',        'API Add-on',            19.99, 5),    -- FLAGGED: agreed $15, billing $19.99
('INV-2024-002', 'Globex Industries', 'Platform License',      38.50, 20),   -- CLEAN
('INV-2024-002', 'Globex Industries', 'Premium Support',       35.00, 1),    -- FLAGGED: agreed $25, billing $35
('INV-2024-003', 'Initech LLC',       'Platform License',      50.00, 15),   -- FLAGGED: agreed $45, billing $50
('INV-2024-003', 'Initech LLC',       'Data Storage (per GB)', 0.12,  500),  -- CLEAN
('INV-2024-004', 'Wayne Enterprises', 'Platform License',      50.00, 25),   -- CLEAN
('INV-2024-004', 'Wayne Enterprises', 'Custom Integration',    250.00, 1),   -- FLAGGED: agreed $200, billing $250
('INV-2024-005', 'Stark Industries',  'Platform License',      55.00, 30);   -- UNMATCHED: no agreed pricing on file