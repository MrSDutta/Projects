-- ============================================
-- SCHEMA: Inventory Audit System V1
-- ============================================

-- 1. Master Inventory (Source of Truth)
CREATE TABLE IF NOT EXISTS master_inventory (
    sku VARCHAR(100) PRIMARY KEY,
    product_name TEXT NOT NULL,
    master_quantity INTEGER NOT NULL,
    master_source VARCHAR(50) NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Inventory Snapshots (What each channel reported)
CREATE TABLE IF NOT EXISTS inventory_snapshots (
    id SERIAL PRIMARY KEY,
    sku VARCHAR(100) NOT NULL,
    channel VARCHAR(30) NOT NULL,
    quantity INTEGER NOT NULL,
    snapshot_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(sku, channel, snapshot_time)
);

-- 3. Audit Log (All reconciliations)
CREATE TABLE IF NOT EXISTS audit_log (
    id SERIAL PRIMARY KEY,
    sku VARCHAR(100) NOT NULL,
    channel VARCHAR(30) NOT NULL,
    action VARCHAR(50) NOT NULL,
    old_quantity INTEGER,
    new_quantity INTEGER,
    status VARCHAR(20) NOT NULL,
    remarks TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- INDEXES for Query Performance
-- ============================================
CREATE INDEX IF NOT EXISTS idx_snapshots_sku ON inventory_snapshots(sku);
CREATE INDEX IF NOT EXISTS idx_snapshots_channel ON inventory_snapshots(channel);
CREATE INDEX IF NOT EXISTS idx_snapshots_time ON inventory_snapshots(snapshot_time DESC);
CREATE INDEX IF NOT EXISTS idx_audit_sku ON audit_log(sku);
CREATE INDEX IF NOT EXISTS idx_audit_status ON audit_log(status);
CREATE INDEX IF NOT EXISTS idx_audit_time ON audit_log(created_at DESC);

-- ============================================
-- SEED DATA: Master Inventory
-- ============================================
TRUNCATE TABLE master_inventory CASCADE;

INSERT INTO master_inventory (sku, product_name, master_quantity, master_source, updated_at) VALUES
('SKU-001', 'Wireless Headphones - Black', 100, 'shopify', NOW()),
('SKU-002', 'USB-C Cable 2m', 250, 'shopify', NOW()),
('SKU-003', 'Phone Case - Blue', 75, 'shopify', NOW()),
('SKU-004', 'Screen Protector 10-pack', 120, 'shopify', NOW()),
('SKU-005', 'Laptop Stand - Silver', 45, 'shopify', NOW()),
('SKU-006', 'Mechanical Keyboard - RGB', 60, 'shopify', NOW()),
('SKU-007', 'Webcam 1080p', 30, 'shopify', NOW()),
('SKU-008', 'Desk Lamp - LED', 80, 'shopify', NOW());

-- ============================================
-- SEED DATA: Inventory Snapshots (Intentional Mismatches for Demo)
-- ============================================
TRUNCATE TABLE inventory_snapshots CASCADE;

INSERT INTO inventory_snapshots (sku, channel, quantity, snapshot_time) VALUES
-- SKU-001: All channels in sync
('SKU-001', 'shopify', 100, NOW() - INTERVAL '10 minutes'),
('SKU-001', 'amazon', 100, NOW() - INTERVAL '10 minutes'),
('SKU-001', 'ebay', 100, NOW() - INTERVAL '10 minutes'),
('SKU-001', 'etsy', 100, NOW() - INTERVAL '10 minutes'),
('SKU-001', 'tiktok', 100, NOW() - INTERVAL '10 minutes'),

-- SKU-002: Minor drift (MONITOR threshold)
('SKU-002', 'shopify', 250, NOW() - INTERVAL '10 minutes'),
('SKU-002', 'amazon', 251, NOW() - INTERVAL '10 minutes'),
('SKU-002', 'ebay', 248, NOW() - INTERVAL '10 minutes'),
('SKU-002', 'etsy', 250, NOW() - INTERVAL '10 minutes'),
('SKU-002', 'tiktok', 250, NOW() - INTERVAL '10 minutes'),

-- SKU-003: Major discrepancy (DISCREPANCY threshold)
('SKU-003', 'shopify', 75, NOW() - INTERVAL '10 minutes'),
('SKU-003', 'amazon', 68, NOW() - INTERVAL '10 minutes'),
('SKU-003', 'ebay', 72, NOW() - INTERVAL '10 minutes'),
('SKU-003', 'etsy', 55, NOW() - INTERVAL '10 minutes'),
('SKU-003', 'tiktok', 75, NOW() - INTERVAL '10 minutes'),

-- SKU-004: One channel way off
('SKU-004', 'shopify', 120, NOW() - INTERVAL '10 minutes'),
('SKU-004', 'amazon', 120, NOW() - INTERVAL '10 minutes'),
('SKU-004', 'ebay', 105, NOW() - INTERVAL '10 minutes'),
('SKU-004', 'etsy', 120, NOW() - INTERVAL '10 minutes'),
('SKU-004', 'tiktok', 120, NOW() - INTERVAL '10 minutes'),

-- SKU-005: Almost in sync
('SKU-005', 'shopify', 45, NOW() - INTERVAL '10 minutes'),
('SKU-005', 'amazon', 45, NOW() - INTERVAL '10 minutes'),
('SKU-005', 'ebay', 47, NOW() - INTERVAL '10 minutes'),
('SKU-005', 'etsy', 45, NOW() - INTERVAL '10 minutes'),
('SKU-005', 'tiktok', 45, NOW() - INTERVAL '10 minutes'),

-- SKU-006: Perfect sync
('SKU-006', 'shopify', 60, NOW() - INTERVAL '10 minutes'),
('SKU-006', 'amazon', 60, NOW() - INTERVAL '10 minutes'),
('SKU-006', 'ebay', 60, NOW() - INTERVAL '10 minutes'),
('SKU-006', 'etsy', 60, NOW() - INTERVAL '10 minutes'),
('SKU-006', 'tiktok', 60, NOW() - INTERVAL '10 minutes'),

-- SKU-007: Widespread drift
('SKU-007', 'shopify', 30, NOW() - INTERVAL '10 minutes'),
('SKU-007', 'amazon', 25, NOW() - INTERVAL '10 minutes'),
('SKU-007', 'ebay', 18, NOW() - INTERVAL '10 minutes'),
('SKU-007', 'etsy', 30, NOW() - INTERVAL '10 minutes'),
('SKU-007', 'tiktok', 28, NOW() - INTERVAL '10 minutes'),

-- SKU-008: Slight variance
('SKU-008', 'shopify', 80, NOW() - INTERVAL '10 minutes'),
('SKU-008', 'amazon', 81, NOW() - INTERVAL '10 minutes'),
('SKU-008', 'ebay', 79, NOW() - INTERVAL '10 minutes'),
('SKU-008', 'etsy', 80, NOW() - INTERVAL '10 minutes'),
('SKU-008', 'tiktok', 80, NOW() - INTERVAL '10 minutes');

-- ============================================
-- SEED DATA: Audit Log (Historical data for demo)
-- ============================================
TRUNCATE TABLE audit_log CASCADE;

INSERT INTO audit_log (sku, channel, action, old_quantity, new_quantity, status, remarks, created_at) VALUES
('SKU-001', 'amazon', 'SNAPSHOT', 100, 100, 'MATCH', 'Perfect sync', NOW() - INTERVAL '1 hour'),
('SKU-002', 'amazon', 'SNAPSHOT', 250, 251, 'MONITOR', 'Drift +1 unit', NOW() - INTERVAL '1 hour'),
('SKU-003', 'etsy', 'SNAPSHOT', 75, 55, 'DISCREPANCY', 'Drift -20 units, critical', NOW() - INTERVAL '1 hour'),
('SKU-004', 'ebay', 'SNAPSHOT', 120, 105, 'DISCREPANCY', 'Drift -15 units', NOW() - INTERVAL '1 hour'),
('SKU-005', 'ebay', 'SNAPSHOT', 45, 47, 'MONITOR', 'Drift +2 units', NOW() - INTERVAL '1 hour'),
('SKU-006', 'shopify', 'SNAPSHOT', 60, 60, 'MATCH', 'Consistent', NOW() - INTERVAL '1 hour'),
('SKU-007', 'ebay', 'SNAPSHOT', 30, 18, 'DISCREPANCY', 'Drift -12 units', NOW() - INTERVAL '1 hour'),
('SKU-007', 'amazon', 'SNAPSHOT', 30, 25, 'MONITOR', 'Drift -5 units', NOW() - INTERVAL '1 hour'),
('SKU-008', 'amazon', 'SNAPSHOT', 80, 81, 'MONITOR', 'Drift +1 unit', NOW() - INTERVAL '1 hour');

-- ============================================
-- QUERIES FOR MVP DASHBOARD
-- ============================================

-- 1. Summary: Current Status by SKU
-- SELECT 
--     sku,
--     product_name,
--     master_quantity,
--     COUNT(CASE WHEN status = 'MATCH' THEN 1 END) as matched_channels,
--     COUNT(CASE WHEN status = 'MONITOR' THEN 1 END) as monitored_channels,
--     COUNT(CASE WHEN status = 'DISCREPANCY' THEN 1 END) as discrepancy_channels,
--     MAX(created_at) as last_audit
-- FROM audit_log
-- JOIN master_inventory ON audit_log.sku = master_inventory.sku
-- WHERE created_at > NOW() - INTERVAL '24 hours'
-- GROUP BY sku, product_name, master_quantity
-- ORDER BY discrepancy_channels DESC;

-- 2. Drift Distribution by Channel
-- SELECT 
--     channel,
--     COUNT(*) as total_skus,
--     COUNT(CASE WHEN status = 'MATCH' THEN 1 END) as matched,
--     COUNT(CASE WHEN status = 'MONITOR' THEN 1 END) as monitored,
--     COUNT(CASE WHEN status = 'DISCREPANCY' THEN 1 END) as discrepancies,
--     ROUND(100.0 * COUNT(CASE WHEN status = 'MATCH' THEN 1 END) / COUNT(*), 1) as match_percent
-- FROM audit_log
-- WHERE created_at > NOW() - INTERVAL '24 hours'
-- GROUP BY channel
-- ORDER BY match_percent ASC;

-- 3. Critical Alerts (DISCREPANCY items)
-- SELECT 
--     sku,
--     channel,
--     old_quantity as master_qty,
--     new_quantity as channel_qty,
--     (new_quantity - old_quantity) as drift,
--     created_at
-- FROM audit_log
-- WHERE status = 'DISCREPANCY'
-- AND created_at > NOW() - INTERVAL '24 hours'
-- ORDER BY ABS(new_quantity - old_quantity) DESC;

-- ============================================
-- END OF SEED SCRIPT
-- ============================================
