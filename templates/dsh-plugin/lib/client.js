/**
 * 网关中台 · 客户端 bundle 模板
 *
 * 三条硬规则：
 *   1. 格式固定为 window.__ModuleLoader__.load({ id, factory })
 *   2. id 必须等于包名
 *   3. factory 里只能 require("react")（最多再加 react/jsx-runtime）——其它模块会
 *      抛 "missed the module table"
 *
 * 不用 JSX/TS：没有编译步骤，全部 React.createElement。
 */
window.__ModuleLoader__.load({
  id: "your-plugin",
  factory: (require) => {
    var module = { exports: {} }
    var exports = module.exports
    Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" })

    const React = require("react")
    const h = React.createElement

    const NS = "your-plugin"
    const BUILD = "your-plugin-v1"

    // 只读接口：令牌由网关侧轮换；不要提交真实令牌到仓库
    const TOKEN = "REPLACE_WITH_TOKEN"
    const ENDPOINT = "https://api.example.com:8443/stats/public.json?k=" + TOKEN

    // ---------- 工具 ----------
    function num(v) {
      const n = Number(v)
      return Number.isFinite(n) ? n : 0
    }

    function group(v) {
      const n = Math.round(num(v))
      const d = String(Math.abs(n))
      let out = ""
      for (let i = 0; i < d.length; i += 1) {
        if (i > 0 && (d.length - i) % 3 === 0) out += ","
        out += d.charAt(i)
      }
      return (n < 0 ? "-" : "") + out
    }

    function usd(v) {
      const n = num(v)
      return n >= 1000 ? "$" + group(n) : "$" + n.toFixed(2)
    }

    // ---------- 数据层（单例 + 订阅） ----------
    const STORE = { status: "idle", data: null, error: "", loadedAt: 0, listeners: new Set() }

    function notify() {
      STORE.listeners.forEach((fn) => { try { fn() } catch (e) { /* 已卸载 */ } })
    }

    let inFlight = null
    function load() {
      if (inFlight !== null) return inFlight
      inFlight = loadOnce().finally(() => { inFlight = null })
      return inFlight
    }

    async function loadOnce() {
      STORE.status = STORE.data === null ? "loading" : "refreshing"
      STORE.error = ""
      notify()
      try {
        // 只带 safelisted 头，避免触发 CORS preflight
        const res = await fetch(ENDPOINT, { headers: { Accept: "application/json" }, cache: "no-store" })
        if (!res.ok) throw new Error("HTTP " + res.status)
        const json = await res.json()
        if (json && json.error) throw new Error(String(json.error))
        STORE.data = json
        STORE.status = "ready"
        STORE.loadedAt = Date.now()
      } catch (error) {
        STORE.status = "error"
        STORE.error = String((error && error.message) || error)
      }
      notify()
    }

    function useStore() {
      const [, bump] = React.useState(0)
      React.useEffect(() => {
        const fn = () => bump((v) => v + 1)
        STORE.listeners.add(fn)
        if (STORE.status === "idle") load()
        return () => { STORE.listeners.delete(fn) }
      }, [])
      return STORE
    }

    // ---------- UI ----------
    const CSS = [
      ".gw-panel{display:flex;flex-direction:column;gap:14px;max-width:1000px;font-size:13px;color:var(--dsw-alias-label-primary)}",
      ".gw-row{display:flex;align-items:center;gap:10px;flex-wrap:wrap}",
      ".gw-title{font-size:17px;font-weight:650}",
      ".gw-meta{font-size:11px;color:var(--dsw-alias-label-secondary)}",
      ".gw-spacer{flex:1}",
      ".gw-btn{height:26px;padding:0 10px;border-radius:7px;border:1px solid var(--dsw-alias-border-l1,rgba(128,128,128,.35));background:transparent;color:var(--dsw-alias-label-secondary);font:inherit;font-size:12px;cursor:pointer}",
      ".gw-btn:hover{color:var(--dsw-alias-label-primary)}",
      ".gw-stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px}",
      ".gw-stat{border:1px solid var(--dsw-alias-border-l1,rgba(128,128,128,.32));border-radius:10px;padding:9px 11px;background:rgba(128,128,128,.06)}",
      ".gw-k{font-size:11px;color:var(--dsw-alias-label-secondary)}",
      ".gw-v{font-size:19px;font-weight:650;font-variant-numeric:tabular-nums}",
      ".gw-s{font-size:10px;color:var(--dsw-alias-label-secondary)}",
      ".gw-table{width:100%;border-collapse:collapse;font-size:12px}",
      ".gw-table th{text-align:left;font-weight:500;font-size:10px;color:var(--dsw-alias-label-secondary);padding:5px 8px;border-bottom:1px solid var(--dsw-alias-border-l1,rgba(128,128,128,.28))}",
      ".gw-table td{padding:4px 8px;border-bottom:1px solid rgba(128,128,128,.12);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:260px}",
      ".gw-num{text-align:right;font-variant-numeric:tabular-nums}",
      ".gw-err{padding:9px 11px;border-radius:9px;border:1px solid var(--dsw-alias-state-error-primary,#ef4444);font-size:12px;word-break:break-word}",
      ".gw-empty{font-size:12px;color:var(--dsw-alias-label-secondary);padding:8px 0}",
    ].join("\n")

    let cssDone = false
    function ensureCss() {
      if (cssDone || typeof document === "undefined") return
      const id = NS + "/panel.css"
      if (document.querySelector('style[data-plugin-css="' + id + '"]') === null) {
        const tag = document.createElement("style")
        tag.dataset.plugin = NS
        tag.dataset.pluginCss = id
        tag.textContent = CSS
        document.head.appendChild(tag)
      }
      cssDone = true
    }

    function Panel(props) {
      ensureCss()
      const store = useStore()
      const data = store.data
      const head = h("div", { className: "gw-row" },
        h("div", { className: "gw-title" }, props.title || "网关中台"),
        h("span", { className: "gw-meta" }, BUILD),
        h("span", { className: "gw-meta" }, data ? String(data.generated_at || "") : ""),
        h("span", { className: "gw-spacer" }),
        h("button", { className: "gw-btn", onClick: () => load() }, "刷新"),
      )

      if (data === null) {
        return h("div", { className: "gw-panel" }, head,
          store.status === "error"
            ? h("div", { className: "gw-err" }, "拉取失败：" + store.error)
            : h("div", { className: "gw-empty" }, "正在拉取…"))
      }

      const s = data.summary_24h || {}
      const models = Array.isArray(data.by_model) ? data.by_model : []
      const total = num(s.success) + num(s.error)
      const rate = total > 0 ? (num(s.success) / total * 100).toFixed(1) + "%" : "—"

      return h("div", { className: "gw-panel" },
        head,
        store.status === "error" ? h("div", { className: "gw-err" }, "上次刷新失败：" + store.error) : null,
        h("div", { className: "gw-stats" },
          h("div", { className: "gw-stat" }, h("div", { className: "gw-k" }, "24h 请求"), h("div", { className: "gw-v" }, group(total)), h("div", { className: "gw-s" }, "失败 " + group(s.error))),
          h("div", { className: "gw-stat" }, h("div", { className: "gw-k" }, "成功率"), h("div", { className: "gw-v" }, rate), h("div", { className: "gw-s" }, "假成功 " + group(s.fake_empty))),
          h("div", { className: "gw-stat" }, h("div", { className: "gw-k" }, "24h 记账折算"), h("div", { className: "gw-v" }, usd(s.used_usd)), h("div", { className: "gw-s" }, "非供应商实扣")),
          h("div", { className: "gw-stat" }, h("div", { className: "gw-k" }, "平均延迟"), h("div", { className: "gw-v" }, num(s.avg_latency_s).toFixed(1) + "s"), h("div", { className: "gw-s" }, "24h")),
        ),
        models.length === 0
          ? h("div", { className: "gw-empty" }, "没有按模型数据")
          : h("table", { className: "gw-table" },
            h("thead", null, h("tr", null,
              ["模型", "请求", "记账", "平均延迟"].map((t) => h("th", { key: t }, t)))),
            h("tbody", null, models.map((m) => h("tr", { key: String(m.model) },
              h("td", null, String(m.model)),
              h("td", { className: "gw-num" }, group(m.requests)),
              h("td", { className: "gw-num" }, usd(m.used_usd)),
              h("td", { className: "gw-num" }, num(m.avg_latency_s).toFixed(1) + "s")))),
          ),
        h("div", { className: "gw-meta" },
          "记账折算 = quota/" + group(num((data.windows || {}).quota_per_usd) || 500000) + "，不等于供应商实扣。"),
      )
    }

    function apply(ctx) {
      ensureCss()
      // 主看板：会话顶部标签页
      ctx.slots.inject("conversation.view", () => ctx.slots.register({
        name: "conversation.view",
        id: NS,
        order: 30,
        label: "网关中台",
      }, () => h(Panel, { title: "网关中台" })))

      // 深度查看：设置里一页（含完整 Key 之类敏感信息时放这里）
      ctx.slots.inject("settings.section", () => ctx.slots.register({
        name: "settings.section",
        id: NS,
        order: 95,
        label: "网关",
        inject: () => ({}),
      }, () => h(Panel, { title: "网关 · 账号与 Key" })))
    }

    exports.NS = NS
    exports.apply = apply
    exports.inject = ["slots"]
    return module.exports
  },
})
