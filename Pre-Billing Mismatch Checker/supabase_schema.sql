-- ============================================
-- VikFlow — Pre-Billing Mismatch Checker
-- Supabase PostgreSQL Schema
-- ============================================

-- 1. Client config — one row per business using this tool
CREATE TABLE IF NOT EXISTS client_configs (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    business_name TEXT NOT NULL,
    billing_source TEXT NOT NULL DEFAULT 'manual',        -- 'stripe', 'quickbooks', 'zoho', 'manual'
    pricing_source TEXT NOT NULL DEFAULT 'manual',        -- 'salesforce', 'hubspot', 'google_sheets', 'manual'
    mismatch_tolerance NUMERIC(10,2) NOT NULL DEFAULT 0.01,
    alert_channel TEXT DEFAULT 'email',                   -- 'email', 'slack', 'both'
    alert_destination TEXT,                                -- email address or slack webhook URL
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Agreed pricing — what was actually promised to the customer
-- This is the "source of truth" table
CREATE TABLE IF NOT EXISTS agreed_pricing (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    config_id UUID REFERENCES client_configs(id) ON DELETE CASCADE,
    account_name TEXT NOT NULL,
    account_id TEXT,                                       -- their CRM account ID, if available
    line_item TEXT NOT NULL,
    agreed_unit_price NUMERIC(12,2) NOT NULL,
    currency TEXT DEFAULT 'USD',
    effective_from DATE DEFAULT CURRENT_DATE,
    effective_until DATE,                                  -- NULL = still active
    source_reference TEXT,                                 -- "Salesforce Opp #12345" or "Email thread 2024-03-15"
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Draft invoices — what billing is about to send out
CREATE TABLE IF NOT EXISTS draft_invoices (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    config_id UUID REFERENCES client_configs(id) ON DELETE CASCADE,
    invoice_id TEXT NOT NULL,                              -- their billing system's invoice ID
    account_name TEXT NOT NULL,
    account_id TEXT,
    line_item TEXT NOT NULL,
    billed_unit_price NUMERIC(12,2) NOT NULL,
    quantity NUMERIC(12,2) DEFAULT 1,
    currency TEXT DEFAULT 'USD',
    invoice_date DATE DEFAULT CURRENT_DATE,
    status TEXT DEFAULT 'pending_review',                  -- 'pending_review', 'clean', 'flagged', 'released', 'revised'
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Mismatch log — every comparison result, pass or fail
CREATE TABLE IF NOT EXISTS mismatch_log (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    config_id UUID REFERENCES client_configs(id) ON DELETE CASCADE,
    draft_invoice_id UUID REFERENCES draft_invoices(id) ON DELETE CASCADE,
    agreed_pricing_id UUID REFERENCES agreed_pricing(id) ON DELETE SET NULL,
    account_name TEXT NOT NULL,
    line_item TEXT NOT NULL,
    agreed_price NUMERIC(12,2),
    billed_price NUMERIC(12,2) NOT NULL,
    deviation NUMERIC(12,2) NOT NULL,
    deviation_pct NUMERIC(6,2),
    match_status TEXT NOT NULL DEFAULT 'flagged',          -- 'clean', 'flagged', 'released', 'revised'
    reviewed_by TEXT,                                      -- who clicked the button
    reviewed_at TIMESTAMPTZ,
    review_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Run log — tracks every execution of the checker
CREATE TABLE IF NOT EXISTS run_log (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    config_id UUID REFERENCES client_configs(id) ON DELETE CASCADE,
    run_at TIMESTAMPTZ DEFAULT NOW(),
    total_invoices_checked INTEGER DEFAULT 0,
    clean_count INTEGER DEFAULT 0,
    flagged_count INTEGER DEFAULT 0,
    unmatched_count INTEGER DEFAULT 0,
    run_status TEXT DEFAULT 'success',                     -- 'success', 'partial_failure', 'failure'
    error_message TEXT
);

-- ============================================
-- Indexes for performance
-- ============================================
CREATE INDEX idx_agreed_pricing_account ON agreed_pricing(config_id, account_name, line_item);
CREATE INDEX idx_draft_invoices_account ON draft_invoices(config_id, account_name, line_item);
CREATE INDEX idx_draft_invoices_status ON draft_invoices(status);
CREATE INDEX idx_mismatch_log_status ON mismatch_log(match_status);
CREATE INDEX idx_mismatch_log_config ON mismatch_log(config_id);

-- ============================================
-- The core comparison function
-- Called by the workflow on each run
-- ============================================
CREATE OR REPLACE FUNCTION run_mismatch_check(p_config_id UUID)
RETURNS TABLE (
    draft_id UUID,
    agreed_id UUID,
    account TEXT,
    item TEXT,
    agreed NUMERIC,
    billed NUMERIC,
    delta NUMERIC,
    delta_pct NUMERIC,
    result TEXT
) AS $$
DECLARE
    v_tolerance NUMERIC;
    v_total INTEGER := 0;
    v_clean INTEGER := 0;
    v_flagged INTEGER := 0;
    v_unmatched INTEGER := 0;
BEGIN
    -- Get tolerance from config
    SELECT mismatch_tolerance INTO v_tolerance
    FROM client_configs WHERE id = p_config_id;

    -- Run comparison for all pending draft invoices
    RETURN QUERY
    WITH comparison AS (
        SELECT
            di.id AS draft_id,
            ap.id AS agreed_id,
            di.account_name AS account,
            di.line_item AS item,
            ap.agreed_unit_price AS agreed,
            di.billed_unit_price AS billed,
            ABS(di.billed_unit_price - COALESCE(ap.agreed_unit_price, 0)) AS delta,
            CASE
                WHEN ap.agreed_unit_price IS NOT NULL AND ap.agreed_unit_price > 0
                THEN ROUND(ABS(di.billed_unit_price - ap.agreed_unit_price) / ap.agreed_unit_price * 100, 2)
                ELSE NULL
            END AS delta_pct,
            CASE
                WHEN ap.id IS NULL THEN 'unmatched'
                WHEN ABS(di.billed_unit_price - ap.agreed_unit_price) <= v_tolerance THEN 'clean'
                ELSE 'flagged'
            END AS result
        FROM draft_invoices di
        LEFT JOIN agreed_pricing ap
            ON di.config_id = ap.config_id
            AND LOWER(TRIM(di.account_name)) = LOWER(TRIM(ap.account_name))
            AND LOWER(TRIM(di.line_item)) = LOWER(TRIM(ap.line_item))
            AND (ap.effective_until IS NULL OR ap.effective_until >= di.invoice_date)
        WHERE di.config_id = p_config_id
            AND di.status = 'pending_review'
    )
    SELECT * FROM comparison;

    -- Count results and log the run
    SELECT COUNT(*) INTO v_total FROM draft_invoices
        WHERE config_id = p_config_id AND status = 'pending_review';

    -- Insert mismatch records and update invoice statuses
    INSERT INTO mismatch_log (config_id, draft_invoice_id, agreed_pricing_id, account_name, line_item, agreed_price, billed_price, deviation, deviation_pct, match_status)
    SELECT p_config_id, c.draft_id, c.agreed_id, c.account, c.item, c.agreed, c.billed, c.delta, c.delta_pct, c.result
    FROM (
        SELECT
            di.id AS draft_id, ap.id AS agreed_id,
            di.account_name AS account, di.line_item AS item,
            ap.agreed_unit_price AS agreed, di.billed_unit_price AS billed,
            ABS(di.billed_unit_price - COALESCE(ap.agreed_unit_price, 0)) AS delta,
            CASE WHEN ap.agreed_unit_price IS NOT NULL AND ap.agreed_unit_price > 0
                THEN ROUND(ABS(di.billed_unit_price - ap.agreed_unit_price) / ap.agreed_unit_price * 100, 2)
                ELSE NULL END AS delta_pct,
            CASE
                WHEN ap.id IS NULL THEN 'unmatched'
                WHEN ABS(di.billed_unit_price - ap.agreed_unit_price) <= v_tolerance THEN 'clean'
                ELSE 'flagged' END AS result
        FROM draft_invoices di
        LEFT JOIN agreed_pricing ap
            ON di.config_id = ap.config_id
            AND LOWER(TRIM(di.account_name)) = LOWER(TRIM(ap.account_name))
            AND LOWER(TRIM(di.line_item)) = LOWER(TRIM(ap.line_item))
            AND (ap.effective_until IS NULL OR ap.effective_until >= di.invoice_date)
        WHERE di.config_id = p_config_id AND di.status = 'pending_review'
    ) c;

    -- Update draft invoice statuses
    UPDATE draft_invoices di SET status = ml.match_status
    FROM mismatch_log ml
    WHERE ml.draft_invoice_id = di.id
        AND di.config_id = p_config_id
        AND di.status = 'pending_review';

    -- Log the run
    SELECT COUNT(*) FILTER (WHERE match_status = 'clean') INTO v_clean FROM mismatch_log WHERE config_id = p_config_id AND created_at > NOW() - INTERVAL '1 minute';
    SELECT COUNT(*) FILTER (WHERE match_status = 'flagged') INTO v_flagged FROM mismatch_log WHERE config_id = p_config_id AND created_at > NOW() - INTERVAL '1 minute';
    SELECT COUNT(*) FILTER (WHERE match_status = 'unmatched') INTO v_unmatched FROM mismatch_log WHERE config_id = p_config_id AND created_at > NOW() - INTERVAL '1 minute';

    INSERT INTO run_log (config_id, total_invoices_checked, clean_count, flagged_count, unmatched_count)
    VALUES (p_config_id, v_total, v_clean, v_flagged, v_unmatched);

END;
$$ LANGUAGE plpgsql;

-- ============================================
-- Action functions (called from the dashboard)
-- ============================================

-- Release a flagged invoice (approve it despite mismatch)
CREATE OR REPLACE FUNCTION release_invoice(p_mismatch_id UUID, p_reviewer TEXT, p_notes TEXT DEFAULT NULL)
RETURNS VOID AS $$
BEGIN
    UPDATE mismatch_log
    SET match_status = 'released', reviewed_by = p_reviewer, reviewed_at = NOW(), review_notes = p_notes
    WHERE id = p_mismatch_id;

    UPDATE draft_invoices
    SET status = 'released'
    WHERE id = (SELECT draft_invoice_id FROM mismatch_log WHERE id = p_mismatch_id);
END;
$$ LANGUAGE plpgsql;

-- Send back for revision
CREATE OR REPLACE FUNCTION revise_invoice(p_mismatch_id UUID, p_reviewer TEXT, p_notes TEXT DEFAULT NULL)
RETURNS VOID AS $$
BEGIN
    UPDATE mismatch_log
    SET match_status = 'revised', reviewed_by = p_reviewer, reviewed_at = NOW(), review_notes = p_notes
    WHERE id = p_mismatch_id;

    UPDATE draft_invoices
    SET status = 'revised'
    WHERE id = (SELECT draft_invoice_id FROM mismatch_log WHERE id = p_mismatch_id);
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- Sample data for testing / demo
-- ============================================
INSERT INTO client_configs (id, business_name, mismatch_tolerance, alert_channel, alert_destination)
VALUES ('00000000-0000-0000-0000-000000000001', 'Demo Company', 0.01, 'slack', 'https://hooks.slack.com/your-webhook');

INSERT INTO agreed_pricing (config_id, account_name, line_item, agreed_unit_price, source_reference) VALUES
('00000000-0000-0000-0000-000000000001', 'Acme Corp',       'Platform License',      42.00, 'Salesforce Opp #1001'),
('00000000-0000-0000-0000-000000000001', 'Acme Corp',       'API Add-on',            15.00, 'Salesforce Opp #1001'),
('00000000-0000-0000-0000-000000000001', 'Globex Industries','Platform License',      38.50, 'Email thread 2024-06-10'),
('00000000-0000-0000-0000-000000000001', 'Globex Industries','Premium Support',       25.00, 'Contract Amendment #3'),
('00000000-0000-0000-0000-000000000001', 'Initech LLC',      'Platform License',      45.00, 'HubSpot Deal #2055'),
('00000000-0000-0000-0000-000000000001', 'Initech LLC',      'Data Storage (per GB)', 0.12,  'HubSpot Deal #2055'),
('00000000-0000-0000-0000-000000000001', 'Wayne Enterprises','Platform License',      50.00, 'Salesforce Opp #3300'),
('00000000-0000-0000-0000-000000000001', 'Wayne Enterprises','Custom Integration',    200.00,'Contract v2 signed 2024-08');

-- Draft invoices — some match, some DON'T (these are the mismatches the tool should catch)
INSERT INTO draft_invoices (config_id, invoice_id, account_name, line_item, billed_unit_price, quantity) VALUES
('00000000-0000-0000-0000-000000000001', 'INV-2024-001', 'Acme Corp',        'Platform License',      42.00, 10),   -- CLEAN
('00000000-0000-0000-0000-000000000001', 'INV-2024-001', 'Acme Corp',        'API Add-on',            19.99, 5),    -- FLAGGED: agreed $15, billing $19.99
('00000000-0000-0000-0000-000000000001', 'INV-2024-002', 'Globex Industries', 'Platform License',      38.50, 20),   -- CLEAN
('00000000-0000-0000-0000-000000000001', 'INV-2024-002', 'Globex Industries', 'Premium Support',       35.00, 1),    -- FLAGGED: agreed $25, billing $35
('00000000-0000-0000-0000-000000000001', 'INV-2024-003', 'Initech LLC',       'Platform License',      50.00, 15),   -- FLAGGED: agreed $45, billing $50
('00000000-0000-0000-0000-000000000001', 'INV-2024-003', 'Initech LLC',       'Data Storage (per GB)', 0.12,  500),  -- CLEAN
('00000000-0000-0000-0000-000000000001', 'INV-2024-004', 'Wayne Enterprises', 'Platform License',      50.00, 25),   -- CLEAN
('00000000-0000-0000-0000-000000000001', 'INV-2024-004', 'Wayne Enterprises', 'Custom Integration',    250.00, 1),   -- FLAGGED: agreed $200, billing $250
('00000000-0000-0000-0000-000000000001', 'INV-2024-005', 'Stark Industries',  'Platform License',      55.00, 30);   -- UNMATCHED: no agreed pricing on file
