-- Default email templates seed
-- Run after schema.sql
-- Edit subject and html before going live with a client

INSERT INTO crm.email_templates (segment, stage, subject, html) VALUES

-- ── Enterprise ────────────────────────────────────────────
('Enterprise', 1,
  'How Enterprise Teams Automate Lead Qualification',
  '<p>Hi {{name}},</p><p>I noticed you''re part of <strong>{{company}}</strong>. Many enterprise teams struggle with identifying high-intent leads quickly.</p><p>We built a lightweight automation workflow that captures inbound leads, enriches company data, and alerts sales when a lead shows real buying intent.</p><p><a href="https://example.com/casestudy?cid={{id}}">View the enterprise case study →</a></p><p><a href="https://example.com/demo?cid={{id}}">Schedule a demo →</a></p><p>Best regards,<br>Team XYZ</p>'
),
('Enterprise', 2,
  'How {{company}} automated lead qualification',
  '<p>Hi {{name}},</p><p>Many enterprise teams automate lead qualification to ensure sales focuses only on the highest-intent prospects.</p><p><a href="https://example.com/case-study?cid={{id}}">See how enterprise teams implement this →</a></p><p><a href="https://example.com/pricing?cid={{id}}">View pricing and deployment options</a></p><p>Best regards,<br>Team XYZ</p>'
),
('Enterprise', 3,
  '15 mins to show you the system?',
  '<p>Hi {{name}},</p><p>If helpful, I can show you how teams like <strong>{{company}}</strong> automate lead qualification in just 15 minutes.</p><p><a href="https://example.com/demo?cid={{id}}">Book a short demo →</a></p><p>Best regards,<br>Team XYZ</p>'
),
('Enterprise', 4,
  'Should I close your file?',
  '<p>Hi {{name}},</p><p>I haven''t heard back. If improving lead qualification at <strong>{{company}}</strong> is still relevant, I''m happy to share more. Otherwise I''ll close your file.</p><p>Best regards,<br>Team XYZ</p>'
),

-- ── Mid-Market ────────────────────────────────────────────
('Mid-Market', 1,
  'A simpler way for {{company}} to automate lead follow-up',
  '<p>Hi {{name}},</p><p>Teams in growing companies like <strong>{{company}}</strong> often struggle with manual lead follow-ups.</p><p><a href="https://example.com/case-study?cid={{id}}">View the workflow overview →</a></p><p>Best regards,<br>Team XYZ</p>'
),
('Mid-Market', 2,
  'How mid-market teams saved 10 hrs/week',
  '<p>Hi {{name}},</p><p>Many mid-market teams automate lead capture and follow-ups to save time and close more deals.</p><p><a href="https://example.com/case-study?cid={{id}}">See the case study →</a></p><p>Best regards,<br>Team XYZ</p>'
),
('Mid-Market', 3,
  'Demo this week?',
  '<p>Hi {{name}},</p><p>I can walk you through how the workflow works specifically for <strong>{{company}}</strong>.</p><p><a href="https://example.com/demo?cid={{id}}">Book a demo →</a></p><p>Best regards,<br>Team XYZ</p>'
),
('Mid-Market', 4,
  'Last email (promise)',
  '<p>Hi {{name}},</p><p>Just checking once more before I close your file. If this is still relevant, happy to help.</p><p>Best regards,<br>Team XYZ</p>'
),

-- ── SMB ───────────────────────────────────────────────────
('SMB', 1,
  'A Simple Way To Make Sure No Lead Slips Through',
  '<p>Hi {{name}},</p><p>Many small teams like <strong>{{company}}</strong> lose leads because follow-ups get delayed.</p><p><a href="https://example.com/case-study?cid={{id}}">See how it works →</a></p><p>Best regards,<br>Team XYZ</p>'
),
('SMB', 2,
  '3 automation wins for small teams',
  '<p>Hi {{name}},</p><p>Here are three ways small teams automate lead follow-ups and close more deals.</p><p><a href="https://example.com/case-study?cid={{id}}">See how small teams automate this →</a></p><p>Best regards,<br>Team XYZ</p>'
),
('SMB', 3,
  'Quick demo?',
  '<p>Hi {{name}},</p><p>I can show how the workflow works for a team like <strong>{{company}}</strong>.</p><p><a href="https://example.com/demo?cid={{id}}">Book a demo →</a></p><p>Best regards,<br>Team XYZ</p>'
),
('SMB', 4,
  'Closing your file',
  '<p>Hi {{name}},</p><p>Just checking once more. If you''d like to revisit later, I''m happy to reconnect.</p><p>Best regards,<br>Team XYZ</p>'
)

ON CONFLICT (segment, stage) DO NOTHING;

-- Verify
SELECT segment, stage, subject FROM crm.email_templates ORDER BY segment, stage;
