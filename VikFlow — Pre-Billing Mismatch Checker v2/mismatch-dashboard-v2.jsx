import { useState, useEffect, useCallback } from "react";

const SUPABASE_URL = "https://YOUR_PROJECT.supabase.co";
const SUPABASE_ANON_KEY = "YOUR_ANON_KEY";
const CONFIG_ID = "00000000-0000-0000-0000-000000000001";

const api = async (table, method = "GET", params = {}, body = null) => {
  const url = new URL(`${SUPABASE_URL}/rest/v1/${table}`);
  Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v));
  const opts = {
    method,
    headers: {
      apikey: SUPABASE_ANON_KEY,
      Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
      "Content-Type": "application/json",
      Prefer: method === "POST" ? "return=representation" : method === "PATCH" ? "return=minimal" : "return=representation",
    },
  };
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(url, opts);
  if (method === "PATCH") return null;
  return res.json();
};

/* ── Styles ── */
const colors = {
  bg: "#F9FAFB", card: "#fff", border: "#E5E7EB", borderLight: "#F3F4F6",
  text: "#111827", textMid: "#374151", textMuted: "#6B7280", textFaint: "#9CA3AF",
  red: "#DC2626", orange: "#EA580C", green: "#16A34A", blue: "#1E40AF", purple: "#5B21B6",
  redBg: "#FEF2F2", orangeBg: "#FFF7ED", greenBg: "#F0FDF4", blueBg: "#EFF6FF", purpleBg: "#F5F3FF",
  redBorder: "#FCA5A5", orangeBorder: "#FDBA74", greenBorder: "#86EFAC", blueBorder: "#93C5FD", purpleBorder: "#C4B5FD",
};

const STATUS_COLORS = {
  flagged:   { bg: colors.redBg,    border: colors.redBorder,    text: "#991B1B", label: "Flagged" },
  unmatched: { bg: colors.orangeBg, border: colors.orangeBorder, text: "#9A3412", label: "Unmatched" },
  clean:     { bg: colors.greenBg,  border: colors.greenBorder,  text: "#166534", label: "Clean" },
  released:  { bg: colors.blueBg,   border: colors.blueBorder,   text: colors.blue, label: "Released" },
  revised:   { bg: colors.purpleBg, border: colors.purpleBorder, text: colors.purple, label: "Revised" },
};

const inputStyle = { padding: "8px 12px", borderRadius: 6, border: `1px solid ${colors.border}`, fontSize: 13, width: "100%", boxSizing: "border-box" };
const btnPrimary = { padding: "8px 18px", fontSize: 13, fontWeight: 600, borderRadius: 6, border: "none", background: colors.text, color: "#fff", cursor: "pointer" };
const btnSecondary = { ...btnPrimary, background: "#fff", color: colors.textMid, border: `1px solid ${colors.border}` };

const Badge = ({ status }) => {
  const s = STATUS_COLORS[status] || STATUS_COLORS.flagged;
  return <span style={{ padding: "3px 10px", borderRadius: 4, fontSize: 12, fontWeight: 600, background: s.bg, border: `1px solid ${s.border}`, color: s.text }}>{s.label}</span>;
};

const StatCard = ({ label, value, accent }) => (
  <div style={{ flex: 1, minWidth: 130, background: colors.card, borderRadius: 10, padding: "16px 18px", border: `1px solid ${colors.border}`, display: "flex", flexDirection: "column", gap: 4 }}>
    <span style={{ fontSize: 12, color: colors.textMuted, fontWeight: 500 }}>{label}</span>
    <span style={{ fontSize: 26, fontWeight: 700, color: accent || colors.text, letterSpacing: "-0.02em" }}>{value}</span>
  </div>
);

const SectionHeader = ({ children, sub }) => (
  <div style={{ marginBottom: 16 }}>
    <h2 style={{ margin: 0, fontSize: 17, fontWeight: 700, color: colors.text }}>{children}</h2>
    {sub && <p style={{ margin: "4px 0 0", fontSize: 13, color: colors.textMuted }}>{sub}</p>}
  </div>
);

/* ── Main Component ── */
export default function MismatchDashboard() {
  const [tab, setTab] = useState("review");
  const [mismatches, setMismatches] = useState([]);
  const [agreedPricing, setAgreedPricing] = useState([]);
  const [runs, setRuns] = useState([]);
  const [filter, setFilter] = useState("flagged");
  const [loading, setLoading] = useState(true);
  const [acting, setActing] = useState(null);
  const [reviewer, setReviewer] = useState("");
  const [reviewNote, setReviewNote] = useState("");
  const [showConfig, setShowConfig] = useState(false);

  // Input form states
  const [pricingForm, setPricingForm] = useState({ account_name: "", line_item: "", agreed_unit_price: "", source_reference: "", remarks: "", entered_by: "" });
  const [invoiceForm, setInvoiceForm] = useState({ invoice_id: "", account_name: "", line_item: "", billed_unit_price: "", quantity: "1", remarks: "" });
  const [submitting, setSubmitting] = useState(false);
  const [successMsg, setSuccessMsg] = useState("");

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [m, r, ap] = await Promise.all([
        api("mismatch_log", "GET", { select: "*", order: "created_at.desc", limit: "100" }),
        api("run_log", "GET", { select: "*", order: "run_at.desc", limit: "5" }),
        api("agreed_pricing", "GET", { select: "*", order: "created_at.desc", limit: "50", config_id: `eq.${CONFIG_ID}` }),
      ]);
      setMismatches(Array.isArray(m) ? m : []);
      setRuns(Array.isArray(r) ? r : []);
      setAgreedPricing(Array.isArray(ap) ? ap : []);
    } catch (e) { console.error(e); }
    setLoading(false);
  }, []);

  useEffect(() => { load(); }, [load]);

  const handleAction = async (id, action) => {
    if (!reviewer.trim()) { alert("Enter your name before taking action."); return; }
    setActing(id);
    const newStatus = action === "release" ? "released" : "revised";
    try {
      await api(`mismatch_log?id=eq.${id}`, "PATCH", {}, { match_status: newStatus, reviewed_by: reviewer, reviewed_at: new Date().toISOString(), review_notes: reviewNote || null });
      const item = mismatches.find((m) => m.id === id);
      if (item?.draft_invoice_id) await api(`draft_invoices?id=eq.${item.draft_invoice_id}`, "PATCH", {}, { status: newStatus });
      setReviewNote("");
      await load();
    } catch (e) { console.error(e); alert("Action failed — check console."); }
    setActing(null);
  };

  const submitPricing = async () => {
    if (!pricingForm.account_name || !pricingForm.line_item || !pricingForm.agreed_unit_price || !pricingForm.entered_by) {
      alert("Fill in account name, line item, agreed price, and your name."); return;
    }
    setSubmitting(true);
    try {
      await api("agreed_pricing", "POST", {}, {
        config_id: CONFIG_ID,
        account_name: pricingForm.account_name.trim(),
        line_item: pricingForm.line_item.trim(),
        agreed_unit_price: parseFloat(pricingForm.agreed_unit_price),
        source_reference: pricingForm.source_reference.trim() || null,
        remarks: pricingForm.remarks.trim() || null,
        entered_by: pricingForm.entered_by.trim(),
        entry_method: "manual",
      });
      setPricingForm({ account_name: "", line_item: "", agreed_unit_price: "", source_reference: "", remarks: "", entered_by: pricingForm.entered_by });
      setSuccessMsg("Agreed pricing saved.");
      setTimeout(() => setSuccessMsg(""), 3000);
      await load();
    } catch (e) { console.error(e); alert("Failed to save — check console."); }
    setSubmitting(false);
  };

  const submitInvoice = async () => {
    if (!invoiceForm.invoice_id || !invoiceForm.account_name || !invoiceForm.line_item || !invoiceForm.billed_unit_price) {
      alert("Fill in invoice ID, account name, line item, and billed price."); return;
    }
    setSubmitting(true);
    try {
      await api("draft_invoices", "POST", {}, {
        config_id: CONFIG_ID,
        invoice_id: invoiceForm.invoice_id.trim(),
        account_name: invoiceForm.account_name.trim(),
        line_item: invoiceForm.line_item.trim(),
        billed_unit_price: parseFloat(invoiceForm.billed_unit_price),
        quantity: parseFloat(invoiceForm.quantity) || 1,
        remarks: invoiceForm.remarks.trim() || null,
        entry_method: "manual",
      });
      setInvoiceForm({ invoice_id: "", account_name: "", line_item: "", billed_unit_price: "", quantity: "1", remarks: "" });
      setSuccessMsg("Draft invoice saved. It will be checked on the next run.");
      setTimeout(() => setSuccessMsg(""), 3000);
      await load();
    } catch (e) { console.error(e); alert("Failed to save — check console."); }
    setSubmitting(false);
  };

  const filtered = mismatches.filter((m) => filter === "all" || m.match_status === filter);
  const counts = {
    total: mismatches.length,
    flagged: mismatches.filter((m) => m.match_status === "flagged").length,
    unmatched: mismatches.filter((m) => m.match_status === "unmatched").length,
    resolved: mismatches.filter((m) => ["released", "revised"].includes(m.match_status)).length,
    leakage: mismatches.filter((m) => m.match_status === "flagged").reduce((s, m) => s + Number(m.deviation || 0), 0),
  };
  const lastRun = runs[0];

  return (
    <div style={{ fontFamily: "'Inter', -apple-system, sans-serif", background: colors.bg, minHeight: "100vh", padding: "24px 20px" }}>
      <div style={{ maxWidth: 1100, margin: "0 auto" }}>

        {/* ── Header ── */}
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: 12, marginBottom: 20 }}>
          <div>
            <h1 style={{ margin: 0, fontSize: 22, fontWeight: 700, color: colors.text }}>Pre-Billing Mismatch Checker</h1>
            <p style={{ margin: "4px 0 0", fontSize: 13, color: colors.textMuted }}>
              {lastRun ? `Last run: ${new Date(lastRun.run_at).toLocaleString()} · ${lastRun.total_invoices_checked} checked · ${lastRun.flagged_count} flagged` : "No runs yet"}
            </p>
          </div>
          <div style={{ display: "flex", gap: 8 }}>
            <button onClick={() => setShowConfig(!showConfig)} style={btnSecondary}>⚙ Config</button>
            <button onClick={load} style={btnPrimary}>↻ Refresh</button>
          </div>
        </div>

        {showConfig && (
          <div style={{ marginBottom: 20, padding: 16, background: colors.card, borderRadius: 8, border: `1px solid ${colors.border}` }}>
            <p style={{ margin: "0 0 8px", fontSize: 13, fontWeight: 600, color: colors.textMid }}>Supabase connection — update these to your project</p>
            <p style={{ margin: 0, fontSize: 12, color: colors.textFaint }}>Edit SUPABASE_URL and SUPABASE_ANON_KEY at the top of the source file, then redeploy.</p>
          </div>
        )}

        {/* ── Tabs ── */}
        <div style={{ display: "flex", gap: 4, marginBottom: 20, borderBottom: `1px solid ${colors.border}`, paddingBottom: 0 }}>
          {[
            { id: "review", label: "Review Mismatches" },
            { id: "input-pricing", label: "Enter Agreed Pricing" },
            { id: "input-invoice", label: "Enter Draft Invoice" },
            { id: "pricing-log", label: "Pricing Records" },
          ].map((t) => (
            <button key={t.id} onClick={() => setTab(t.id)} style={{
              padding: "10px 18px", fontSize: 13, fontWeight: 600, cursor: "pointer", border: "none", borderBottom: tab === t.id ? `2px solid ${colors.text}` : "2px solid transparent",
              background: "transparent", color: tab === t.id ? colors.text : colors.textMuted,
            }}>
              {t.label}
            </button>
          ))}
        </div>

        {successMsg && (
          <div style={{ marginBottom: 16, padding: "10px 16px", background: colors.greenBg, border: `1px solid ${colors.greenBorder}`, borderRadius: 6, fontSize: 13, color: "#166534", fontWeight: 500 }}>
            {successMsg}
          </div>
        )}

        {/* ══════════ TAB: REVIEW MISMATCHES ══════════ */}
        {tab === "review" && (
          <>
            {/* Stats */}
            <div style={{ display: "flex", gap: 12, flexWrap: "wrap", marginBottom: 16 }}>
              <StatCard label="Total Checks" value={counts.total} />
              <StatCard label="Flagged" value={counts.flagged} accent={colors.red} />
              <StatCard label="Unmatched" value={counts.unmatched} accent={colors.orange} />
              <StatCard label="Resolved" value={counts.resolved} accent={colors.green} />
              <StatCard label="Potential Leakage" value={`$${counts.leakage.toFixed(2)}`} accent={colors.red} />
            </div>

            {/* Reviewer + Filter */}
            <div style={{ display: "flex", gap: 12, alignItems: "center", flexWrap: "wrap", marginBottom: 16 }}>
              <input value={reviewer} onChange={(e) => setReviewer(e.target.value)} placeholder="Your name (required to act)" style={{ ...inputStyle, width: 220 }} />
              <input value={reviewNote} onChange={(e) => setReviewNote(e.target.value)} placeholder="Review note (optional)" style={{ ...inputStyle, width: 260 }} />
              <div style={{ display: "flex", gap: 4, marginLeft: "auto" }}>
                {["flagged", "unmatched", "all"].map((f) => (
                  <button key={f} onClick={() => setFilter(f)} style={{
                    padding: "6px 14px", fontSize: 12, fontWeight: 600, borderRadius: 6, cursor: "pointer",
                    border: filter === f ? "none" : `1px solid ${colors.border}`,
                    background: filter === f ? colors.text : colors.card, color: filter === f ? "#fff" : colors.textMid,
                  }}>{f.charAt(0).toUpperCase() + f.slice(1)}</button>
                ))}
              </div>
            </div>

            {/* Table */}
            <div style={{ background: colors.card, borderRadius: 10, border: `1px solid ${colors.border}`, overflow: "auto" }}>
              {loading ? (
                <p style={{ padding: 40, textAlign: "center", color: colors.textFaint, fontSize: 14 }}>Loading…</p>
              ) : filtered.length === 0 ? (
                <p style={{ padding: 40, textAlign: "center", color: colors.textFaint, fontSize: 14 }}>
                  {filter === "flagged" ? "No mismatches to review — all clean." : "No records match this filter."}
                </p>
              ) : (
                <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
                  <thead>
                    <tr style={{ borderBottom: `1px solid ${colors.border}` }}>
                      {["Account", "Line Item", "Agreed", "Billed", "Deviation", "Status", "Actions"].map((h) => (
                        <th key={h} style={{ padding: "10px 14px", textAlign: "left", fontWeight: 600, color: colors.textMuted, fontSize: 11, textTransform: "uppercase", letterSpacing: "0.05em" }}>{h}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {filtered.map((m) => (
                      <tr key={m.id} style={{ borderBottom: `1px solid ${colors.borderLight}` }}>
                        <td style={{ padding: "10px 14px", fontWeight: 500, color: colors.text }}>{m.account_name}</td>
                        <td style={{ padding: "10px 14px", color: colors.textMid }}>{m.line_item}</td>
                        <td style={{ padding: "10px 14px", color: colors.textMid, fontVariantNumeric: "tabular-nums" }}>{m.agreed_price != null ? `$${Number(m.agreed_price).toFixed(2)}` : "—"}</td>
                        <td style={{ padding: "10px 14px", color: colors.textMid, fontVariantNumeric: "tabular-nums" }}>${Number(m.billed_price).toFixed(2)}</td>
                        <td style={{ padding: "10px 14px", fontWeight: 600, color: m.deviation > 0 ? colors.red : colors.green, fontVariantNumeric: "tabular-nums" }}>{m.deviation > 0 ? `+$${Number(m.deviation).toFixed(2)}` : "$0.00"}</td>
                        <td style={{ padding: "10px 14px" }}><Badge status={m.match_status} /></td>
                        <td style={{ padding: "10px 14px" }}>
                          {["flagged", "unmatched"].includes(m.match_status) ? (
                            <div style={{ display: "flex", gap: 6 }}>
                              <button disabled={acting === m.id} onClick={() => handleAction(m.id, "release")} style={{ padding: "5px 10px", fontSize: 12, fontWeight: 600, borderRadius: 5, border: "none", cursor: "pointer", background: colors.blueBg, color: colors.blue, opacity: acting === m.id ? 0.5 : 1 }}>Override & Release</button>
                              <button disabled={acting === m.id} onClick={() => handleAction(m.id, "revise")} style={{ padding: "5px 10px", fontSize: 12, fontWeight: 600, borderRadius: 5, border: "none", cursor: "pointer", background: "#FEF3C7", color: "#92400E", opacity: acting === m.id ? 0.5 : 1 }}>Request Revision</button>
                            </div>
                          ) : (
                            <span style={{ fontSize: 12, color: colors.textFaint }}>{m.reviewed_by ? `${m.match_status} by ${m.reviewed_by}` : "—"}</span>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>
          </>
        )}

        {/* ══════════ TAB: ENTER AGREED PRICING ══════════ */}
        {tab === "input-pricing" && (
          <div style={{ background: colors.card, borderRadius: 10, border: `1px solid ${colors.border}`, padding: 24 }}>
            <SectionHeader sub="After a sales negotiation, enter the agreed pricing here. This becomes the source of truth that every future invoice is checked against.">
              Enter Agreed Pricing
            </SectionHeader>

            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16, marginBottom: 16 }}>
              <div>
                <label style={{ display: "block", fontSize: 12, fontWeight: 600, color: colors.textMid, marginBottom: 4 }}>Account / Customer Name *</label>
                <input value={pricingForm.account_name} onChange={(e) => setPricingForm({ ...pricingForm, account_name: e.target.value })} placeholder="e.g. Acme Corp" style={inputStyle} />
              </div>
              <div>
                <label style={{ display: "block", fontSize: 12, fontWeight: 600, color: colors.textMid, marginBottom: 4 }}>Line Item / Product *</label>
                <input value={pricingForm.line_item} onChange={(e) => setPricingForm({ ...pricingForm, line_item: e.target.value })} placeholder="e.g. Platform License" style={inputStyle} />
              </div>
              <div>
                <label style={{ display: "block", fontSize: 12, fontWeight: 600, color: colors.textMid, marginBottom: 4 }}>Agreed Unit Price ($) *</label>
                <input type="number" step="0.01" value={pricingForm.agreed_unit_price} onChange={(e) => setPricingForm({ ...pricingForm, agreed_unit_price: e.target.value })} placeholder="e.g. 42.00" style={inputStyle} />
              </div>
              <div>
                <label style={{ display: "block", fontSize: 12, fontWeight: 600, color: colors.textMid, marginBottom: 4 }}>Your Name *</label>
                <input value={pricingForm.entered_by} onChange={(e) => setPricingForm({ ...pricingForm, entered_by: e.target.value })} placeholder="e.g. Raj Mehta" style={inputStyle} />
              </div>
              <div>
                <label style={{ display: "block", fontSize: 12, fontWeight: 600, color: colors.textMid, marginBottom: 4 }}>Source Reference</label>
                <input value={pricingForm.source_reference} onChange={(e) => setPricingForm({ ...pricingForm, source_reference: e.target.value })} placeholder="e.g. HubSpot Deal #1234, Email thread, Verbal" style={inputStyle} />
              </div>
              <div>
                <label style={{ display: "block", fontSize: 12, fontWeight: 600, color: colors.textMid, marginBottom: 4 }}>Remarks</label>
                <input value={pricingForm.remarks} onChange={(e) => setPricingForm({ ...pricingForm, remarks: e.target.value })} placeholder="e.g. Volume discount for 20+ seats, valid until Dec 2025" style={inputStyle} />
              </div>
            </div>

            <button onClick={submitPricing} disabled={submitting} style={{ ...btnPrimary, opacity: submitting ? 0.5 : 1 }}>
              {submitting ? "Saving…" : "Save Agreed Pricing"}
            </button>
          </div>
        )}

        {/* ══════════ TAB: ENTER DRAFT INVOICE ══════════ */}
        {tab === "input-invoice" && (
          <div style={{ background: colors.card, borderRadius: 10, border: `1px solid ${colors.border}`, padding: 24 }}>
            <SectionHeader sub="Enter a draft invoice line item to be checked against agreed pricing. For automated entry, connect your billing system via webhook instead.">
              Enter Draft Invoice
            </SectionHeader>

            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16, marginBottom: 16 }}>
              <div>
                <label style={{ display: "block", fontSize: 12, fontWeight: 600, color: colors.textMid, marginBottom: 4 }}>Invoice ID *</label>
                <input value={invoiceForm.invoice_id} onChange={(e) => setInvoiceForm({ ...invoiceForm, invoice_id: e.target.value })} placeholder="e.g. INV-2024-006" style={inputStyle} />
              </div>
              <div>
                <label style={{ display: "block", fontSize: 12, fontWeight: 600, color: colors.textMid, marginBottom: 4 }}>Account / Customer Name *</label>
                <input value={invoiceForm.account_name} onChange={(e) => setInvoiceForm({ ...invoiceForm, account_name: e.target.value })} placeholder="e.g. Acme Corp" style={inputStyle} />
              </div>
              <div>
                <label style={{ display: "block", fontSize: 12, fontWeight: 600, color: colors.textMid, marginBottom: 4 }}>Line Item / Product *</label>
                <input value={invoiceForm.line_item} onChange={(e) => setInvoiceForm({ ...invoiceForm, line_item: e.target.value })} placeholder="e.g. Platform License" style={inputStyle} />
              </div>
              <div>
                <label style={{ display: "block", fontSize: 12, fontWeight: 600, color: colors.textMid, marginBottom: 4 }}>Billed Unit Price ($) *</label>
                <input type="number" step="0.01" value={invoiceForm.billed_unit_price} onChange={(e) => setInvoiceForm({ ...invoiceForm, billed_unit_price: e.target.value })} placeholder="e.g. 50.00" style={inputStyle} />
              </div>
              <div>
                <label style={{ display: "block", fontSize: 12, fontWeight: 600, color: colors.textMid, marginBottom: 4 }}>Quantity</label>
                <input type="number" step="1" value={invoiceForm.quantity} onChange={(e) => setInvoiceForm({ ...invoiceForm, quantity: e.target.value })} placeholder="1" style={inputStyle} />
              </div>
              <div>
                <label style={{ display: "block", fontSize: 12, fontWeight: 600, color: colors.textMid, marginBottom: 4 }}>Remarks</label>
                <input value={invoiceForm.remarks} onChange={(e) => setInvoiceForm({ ...invoiceForm, remarks: e.target.value })} placeholder="e.g. Monthly recurring, includes overage" style={inputStyle} />
              </div>
            </div>

            <button onClick={submitInvoice} disabled={submitting} style={{ ...btnPrimary, opacity: submitting ? 0.5 : 1 }}>
              {submitting ? "Saving…" : "Save Draft Invoice"}
            </button>
          </div>
        )}

        {/* ══════════ TAB: PRICING LOG ══════════ */}
        {tab === "pricing-log" && (
          <div style={{ background: colors.card, borderRadius: 10, border: `1px solid ${colors.border}`, overflow: "auto" }}>
            <div style={{ padding: "16px 20px", borderBottom: `1px solid ${colors.border}` }}>
              <SectionHeader sub="All agreed pricing records currently on file. This is what every invoice gets checked against.">
                Pricing Records
              </SectionHeader>
            </div>
            {agreedPricing.length === 0 ? (
              <p style={{ padding: 40, textAlign: "center", color: colors.textFaint, fontSize: 14 }}>No pricing records yet. Use the "Enter Agreed Pricing" tab to add one.</p>
            ) : (
              <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
                <thead>
                  <tr style={{ borderBottom: `1px solid ${colors.border}` }}>
                    {["Account", "Line Item", "Agreed Price", "Source", "Remarks", "Entered By", "Date"].map((h) => (
                      <th key={h} style={{ padding: "10px 14px", textAlign: "left", fontWeight: 600, color: colors.textMuted, fontSize: 11, textTransform: "uppercase", letterSpacing: "0.05em" }}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {agreedPricing.map((ap) => (
                    <tr key={ap.id} style={{ borderBottom: `1px solid ${colors.borderLight}` }}>
                      <td style={{ padding: "10px 14px", fontWeight: 500, color: colors.text }}>{ap.account_name}</td>
                      <td style={{ padding: "10px 14px", color: colors.textMid }}>{ap.line_item}</td>
                      <td style={{ padding: "10px 14px", color: colors.textMid, fontVariantNumeric: "tabular-nums" }}>${Number(ap.agreed_unit_price).toFixed(2)}</td>
                      <td style={{ padding: "10px 14px", color: colors.textMuted, fontSize: 12 }}>{ap.source_reference || "—"}</td>
                      <td style={{ padding: "10px 14px", color: colors.textMuted, fontSize: 12, maxWidth: 200, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{ap.remarks || "—"}</td>
                      <td style={{ padding: "10px 14px", color: colors.textMid, fontSize: 12 }}>{ap.entered_by || "—"}</td>
                      <td style={{ padding: "10px 14px", color: colors.textMuted, fontSize: 12 }}>{new Date(ap.created_at).toLocaleDateString()}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        )}

        {/* Footer */}
        <p style={{ margin: "20px 0 0", fontSize: 11, color: colors.textFaint, textAlign: "center" }}>
          VikFlow — Pre-Billing Mismatch Checker v2 · Revenue Leakage Audit Framework
        </p>
      </div>
    </div>
  );
}
