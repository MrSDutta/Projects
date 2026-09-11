import { useState, useEffect, useCallback } from "react";

const SUPABASE_URL = "https://YOUR_PROJECT.supabase.co";
const SUPABASE_ANON_KEY = "YOUR_ANON_KEY";

const api = async (table, method = "GET", params = {}, body = null) => {
  const url = new URL(`${SUPABASE_URL}/rest/v1/${table}`);
  Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v));
  const opts = {
    method,
    headers: {
      apikey: SUPABASE_ANON_KEY,
      Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
      "Content-Type": "application/json",
      Prefer: method === "PATCH" ? "return=minimal" : "return=representation",
    },
  };
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(url, opts);
  if (method === "PATCH") return null;
  return res.json();
};

const STATUS_COLORS = {
  flagged: { bg: "#FEF2F2", border: "#FCA5A5", text: "#991B1B", label: "Flagged" },
  unmatched: { bg: "#FFF7ED", border: "#FDBA74", text: "#9A3412", label: "Unmatched" },
  clean: { bg: "#F0FDF4", border: "#86EFAC", text: "#166534", label: "Clean" },
  released: { bg: "#EFF6FF", border: "#93C5FD", text: "#1E40AF", label: "Released" },
  revised: { bg: "#F5F3FF", border: "#C4B5FD", text: "#5B21B6", label: "Revised" },
};

const Badge = ({ status }) => {
  const s = STATUS_COLORS[status] || STATUS_COLORS.flagged;
  return (
    <span style={{ padding: "3px 10px", borderRadius: 4, fontSize: 12, fontWeight: 600, background: s.bg, border: `1px solid ${s.border}`, color: s.text }}>
      {s.label}
    </span>
  );
};

const StatCard = ({ label, value, accent }) => (
  <div style={{ flex: 1, minWidth: 140, background: "#fff", borderRadius: 10, padding: "18px 20px", border: "1px solid #E5E7EB", display: "flex", flexDirection: "column", gap: 4 }}>
    <span style={{ fontSize: 13, color: "#6B7280", fontWeight: 500 }}>{label}</span>
    <span style={{ fontSize: 28, fontWeight: 700, color: accent || "#111827", letterSpacing: "-0.02em" }}>{value}</span>
  </div>
);

export default function MismatchDashboard() {
  const [mismatches, setMismatches] = useState([]);
  const [runs, setRuns] = useState([]);
  const [filter, setFilter] = useState("flagged");
  const [loading, setLoading] = useState(true);
  const [acting, setActing] = useState(null);
  const [reviewer, setReviewer] = useState("");
  const [showConfig, setShowConfig] = useState(false);
  const [config, setConfig] = useState({ url: SUPABASE_URL, key: SUPABASE_ANON_KEY });

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [m, r] = await Promise.all([
        api("mismatch_log", "GET", { select: "*", order: "created_at.desc", limit: "100" }),
        api("run_log", "GET", { select: "*", order: "run_at.desc", limit: "5" }),
      ]);
      setMismatches(Array.isArray(m) ? m : []);
      setRuns(Array.isArray(r) ? r : []);
    } catch (e) {
      console.error(e);
    }
    setLoading(false);
  }, []);

  useEffect(() => { load(); }, [load]);

  const handleAction = async (id, action) => {
    if (!reviewer.trim()) { alert("Enter your name before taking action."); return; }
    setActing(id);
    const newStatus = action === "release" ? "released" : "revised";
    try {
      await api(`mismatch_log?id=eq.${id}`, "PATCH", {}, { match_status: newStatus, reviewed_by: reviewer, reviewed_at: new Date().toISOString() });
      const item = mismatches.find((m) => m.id === id);
      if (item?.draft_invoice_id) {
        await api(`draft_invoices?id=eq.${item.draft_invoice_id}`, "PATCH", {}, { status: newStatus });
      }
      await load();
    } catch (e) {
      console.error(e);
      alert("Action failed — check console.");
    }
    setActing(null);
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
    <div style={{ fontFamily: "'Inter', -apple-system, sans-serif", background: "#F9FAFB", minHeight: "100vh", padding: "24px 20px" }}>
      {/* Header */}
      <div style={{ maxWidth: 1100, margin: "0 auto 24px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: 12 }}>
          <div>
            <h1 style={{ margin: 0, fontSize: 22, fontWeight: 700, color: "#111827", letterSpacing: "-0.01em" }}>
              Pre-Billing Mismatch Checker
            </h1>
            <p style={{ margin: "4px 0 0", fontSize: 13, color: "#6B7280" }}>
              {lastRun
                ? `Last run: ${new Date(lastRun.run_at).toLocaleString()} · ${lastRun.total_invoices_checked} checked · ${lastRun.flagged_count} flagged`
                : "No runs yet"}
            </p>
          </div>
          <div style={{ display: "flex", gap: 8 }}>
            <button onClick={() => setShowConfig(!showConfig)} style={{ padding: "7px 14px", fontSize: 13, borderRadius: 6, border: "1px solid #D1D5DB", background: "#fff", cursor: "pointer", color: "#374151" }}>
              ⚙ Config
            </button>
            <button onClick={load} style={{ padding: "7px 14px", fontSize: 13, borderRadius: 6, border: "none", background: "#111827", color: "#fff", cursor: "pointer", fontWeight: 600 }}>
              ↻ Refresh
            </button>
          </div>
        </div>

        {showConfig && (
          <div style={{ marginTop: 16, padding: 16, background: "#fff", borderRadius: 8, border: "1px solid #E5E7EB" }}>
            <p style={{ margin: "0 0 10px", fontSize: 13, fontWeight: 600, color: "#374151" }}>
              Connection — update these to point at your own Supabase project
            </p>
            <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
              <input value={config.url} onChange={(e) => setConfig({ ...config, url: e.target.value })} placeholder="Supabase URL" style={{ flex: 2, minWidth: 200, padding: "8px 10px", borderRadius: 6, border: "1px solid #D1D5DB", fontSize: 13 }} />
              <input value={config.key} onChange={(e) => setConfig({ ...config, key: e.target.value })} placeholder="Anon Key" style={{ flex: 3, minWidth: 280, padding: "8px 10px", borderRadius: 6, border: "1px solid #D1D5DB", fontSize: 13 }} />
            </div>
            <p style={{ margin: "8px 0 0", fontSize: 11, color: "#9CA3AF" }}>
              Changes require a page reload to take effect. These are stored in-session only.
            </p>
          </div>
        )}
      </div>

      {/* Stats */}
      <div style={{ maxWidth: 1100, margin: "0 auto 20px", display: "flex", gap: 12, flexWrap: "wrap" }}>
        <StatCard label="Total Checks" value={counts.total} />
        <StatCard label="Flagged" value={counts.flagged} accent="#DC2626" />
        <StatCard label="Unmatched" value={counts.unmatched} accent="#EA580C" />
        <StatCard label="Resolved" value={counts.resolved} accent="#16A34A" />
        <StatCard label="Potential Leakage" value={`$${counts.leakage.toFixed(2)}`} accent="#DC2626" />
      </div>

      {/* Reviewer + Filter */}
      <div style={{ maxWidth: 1100, margin: "0 auto 16px", display: "flex", gap: 12, alignItems: "center", flexWrap: "wrap" }}>
        <input value={reviewer} onChange={(e) => setReviewer(e.target.value)} placeholder="Your name (required to take action)" style={{ padding: "8px 12px", borderRadius: 6, border: "1px solid #D1D5DB", fontSize: 13, width: 260 }} />
        <div style={{ display: "flex", gap: 4, marginLeft: "auto" }}>
          {["flagged", "unmatched", "all"].map((f) => (
            <button key={f} onClick={() => setFilter(f)} style={{
              padding: "6px 14px", fontSize: 12, fontWeight: 600, borderRadius: 6, cursor: "pointer",
              border: filter === f ? "none" : "1px solid #D1D5DB",
              background: filter === f ? "#111827" : "#fff",
              color: filter === f ? "#fff" : "#374151",
            }}>
              {f.charAt(0).toUpperCase() + f.slice(1)}
            </button>
          ))}
        </div>
      </div>

      {/* Table */}
      <div style={{ maxWidth: 1100, margin: "0 auto", background: "#fff", borderRadius: 10, border: "1px solid #E5E7EB", overflow: "auto" }}>
        {loading ? (
          <p style={{ padding: 40, textAlign: "center", color: "#9CA3AF", fontSize: 14 }}>Loading…</p>
        ) : filtered.length === 0 ? (
          <p style={{ padding: 40, textAlign: "center", color: "#9CA3AF", fontSize: 14 }}>
            {filter === "flagged" ? "No mismatches to review — all clean." : "No records match this filter."}
          </p>
        ) : (
          <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
            <thead>
              <tr style={{ borderBottom: "1px solid #E5E7EB" }}>
                {["Account", "Line Item", "Agreed", "Billed", "Deviation", "Status", "Actions"].map((h) => (
                  <th key={h} style={{ padding: "10px 14px", textAlign: "left", fontWeight: 600, color: "#6B7280", fontSize: 11, textTransform: "uppercase", letterSpacing: "0.05em" }}>
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {filtered.map((m) => (
                <tr key={m.id} style={{ borderBottom: "1px solid #F3F4F6" }}>
                  <td style={{ padding: "10px 14px", fontWeight: 500, color: "#111827" }}>{m.account_name}</td>
                  <td style={{ padding: "10px 14px", color: "#374151" }}>{m.line_item}</td>
                  <td style={{ padding: "10px 14px", color: "#374151", fontVariantNumeric: "tabular-nums" }}>
                    {m.agreed_price != null ? `$${Number(m.agreed_price).toFixed(2)}` : "—"}
                  </td>
                  <td style={{ padding: "10px 14px", color: "#374151", fontVariantNumeric: "tabular-nums" }}>
                    ${Number(m.billed_price).toFixed(2)}
                  </td>
                  <td style={{ padding: "10px 14px", fontWeight: 600, color: m.deviation > 0 ? "#DC2626" : "#16A34A", fontVariantNumeric: "tabular-nums" }}>
                    {m.deviation > 0 ? `+$${Number(m.deviation).toFixed(2)}` : "$0.00"}
                  </td>
                  <td style={{ padding: "10px 14px" }}><Badge status={m.match_status} /></td>
                  <td style={{ padding: "10px 14px" }}>
                    {["flagged", "unmatched"].includes(m.match_status) ? (
                      <div style={{ display: "flex", gap: 6 }}>
                        <button disabled={acting === m.id} onClick={() => handleAction(m.id, "release")} style={{
                          padding: "5px 10px", fontSize: 12, fontWeight: 600, borderRadius: 5, border: "none", cursor: "pointer",
                          background: "#DBEAFE", color: "#1E40AF", opacity: acting === m.id ? 0.5 : 1,
                        }}>
                          Override & Release
                        </button>
                        <button disabled={acting === m.id} onClick={() => handleAction(m.id, "revise")} style={{
                          padding: "5px 10px", fontSize: 12, fontWeight: 600, borderRadius: 5, border: "none", cursor: "pointer",
                          background: "#FEF3C7", color: "#92400E", opacity: acting === m.id ? 0.5 : 1,
                        }}>
                          Request Revision
                        </button>
                      </div>
                    ) : (
                      <span style={{ fontSize: 12, color: "#9CA3AF" }}>
                        {m.reviewed_by ? `${m.match_status} by ${m.reviewed_by}` : "—"}
                      </span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* Footer */}
      <p style={{ maxWidth: 1100, margin: "20px auto 0", fontSize: 11, color: "#9CA3AF", textAlign: "center" }}>
        VikFlow — Pre-Billing Mismatch Checker · Revenue Leakage Audit Framework
      </p>
    </div>
  );
}
