# 团队数据中台：DSH Desktop 客户端插件 + 只读统计接口

把一个自建网关的资产、额度、健康、用量做成团队常驻面板，做法分三层，可以只做前两层。

| 层 | 产出 | 谁能用 |
| --- | --- | --- |
| 1. 数据 | 网关侧一个带令牌的只读 JSON 接口 | 任何客户端（网页、脚本、插件） |
| 2. 面板 | 装在本机 DSH Desktop 里的客户端插件 | 用 DSH Desktop 的伙伴 |
| 3. 告警 | 网关机器上的 cron + 消息渠道 | 需要离线也能收到提醒的团队 |

> 本文所有 `api.example.com` / `203.0.113.10` / `REPLACE_WITH_TOKEN` 都是占位符，替换成你自己的。
> 这份文档基于 2026-11 一次真实接入过程回写，**第 3 节的失败模式全部实际发生过**。

---

## 1. 先决条件

- 网关已按本仓库其余部分部署完成（New API 在跑，`/opt/your-gateway/data/new-api/one-api.db` 存在）。
- DSH Desktop 已安装（本文按 2.x 实测；其它版本请先核对 `package.json` 的版本号）。
- 你拥有该机器的 SSH 权限，且**清楚当前 IP 是哪一台**（见 4.4 的教训）。

---

## 2. 第一层：只读统计接口

### 2.1 为什么单独开一个令牌接口，而不是复用面板

面板是单页应用，登录会话会被挤掉、Basic Auth 会拦住 XHR、跨域也不友好。给看板单独开一条**只读 + 令牌校验 + 允许跨域**的路由，前端和脚本都能稳定读取。

nginx 片段（放在你的 TLS server 块内）：

```nginx
location = /stats/public.json {
    auth_basic off;
    if ($arg_k = "") { return 403; }
    if ($arg_k != "REPLACE_WITH_TOKEN") { return 403; }
    add_header Access-Control-Allow-Origin "*" always;
    add_header Cache-Control "no-store" always;
    proxy_pass http://127.0.0.1:9101/live.json;
    proxy_buffering off;
    proxy_read_timeout 40s;
}
```

要点：

- **令牌校验放在 nginx**，应用侧完全不碰鉴权。
- `add_header ... always` 保证 403 响应也带 CORS 头，否则浏览器只会报一个看不出原因的跨域错误。
- 令牌必须是**长随机串**；它等价于这把数据钥匙，泄漏后要能一条命令轮换（改 nginx + reload 即可）。
- 前端请求**不要带自定义头**（只带 `Accept` 这类 safelisted 头），这样可以避免 preflight，省掉一半排障。

### 2.2 数据形状（建议）

一个 JSON 里放全，前端一次取完，避免多请求拼接：

```jsonc
{
  "generated_at": "2026-01-01 12:00",
  "generated_at_epoch": 1767225600,
  "accounts": [ { "user_id": 1, "username": "alice", "display_name": "Alice",
                  "quota_usd": 1000.0, "used_usd": 12.34, "requests": 42,
                  "tokens": [ { "id": 2, "name": "prod", "key": "sk-...",
                                "status": 1, "created": "...", "accessed": "...",
                                "unlimited": false, "model_limited": true,
                                "model_limits": "gpt-4o", "used_usd": 1.23 } ] } ],
  "summary_24h": { "success": 100, "error": 2, "fake_empty": 0,
                   "prompt_tokens": 1000000, "completion_tokens": 20000,
                   "used_usd": 1.5, "avg_latency_s": 3.2 },
  "by_model": [ { "model": "gpt-4o", "requests": 80, "used_usd": 1.2,
                  "prompt_tokens": 800000, "completion_tokens": 15000,
                  "avg_latency_s": 3.0, "max_latency_s": 9 } ],
  "by_user": [ { "username": "alice", "display_name": "Alice",
                 "requests": 60, "used_usd": 0.9,
                 "prompt_tokens": 600000, "completion_tokens": 12000 } ],
  "usage_daily": [ { "date": "2026-01-01", "requests": 100, "used_usd": 1.5,
                     "prompt_tokens": 1000000, "completion_tokens": 20000,
                     "errors": 2 } ],
  "vps": { "ok": true, "monthly_gib": 1000, "used_gib": 271.2,
           "percent": 27.1, "reset": "2026-01-05", "suspended": false },
  "windows": { "daily_days": 84, "summary_days": 30, "quota_per_usd": 500000 }
}
```

`windows` 这一段很重要：把口径写进响应，前端原样展示，避免"这个数字是 24 小时还是 30 天"的扯皮。

### 2.3 金额口径（最容易错的地方）

New API 的 `quota` 是计数器，`quota / QuotaPerUnit`（默认 500000）才是"记账美元"。

- **它是记账折算，不是供应商实扣。** 订阅转发场景下真实现金成本为 0，这个数字只用于比较相对消耗速度。
- 自检方法：`SUM(users.used_quota)` 与 `SUM(logs.quota)` 应基本相等，两条独立路径互验。
- 常见错误：拿到已经折算过的美元值，又除了一次 500000，结果小三个数量级。

### 2.4 聚合 SQL（SQLite 只读）

```python
con = sqlite3.connect("file:/opt/your-gateway/data/new-api/one-api.db?mode=ro", uri=True)
# 逐日（84 天，热力图用）
SELECT date(created_at,'unixepoch','localtime') d, COUNT(*), SUM(prompt_tokens),
       SUM(completion_tokens), SUM(quota)
FROM logs WHERE type=2 AND created_at>=? GROUP BY d ORDER BY d;
# 按模型 / 按人（30 天）
SELECT model_name, COUNT(*), SUM(prompt_tokens), SUM(completion_tokens), SUM(quota),
       AVG(use_time), MAX(use_time)
FROM logs WHERE type=2 AND created_at>=? GROUP BY model_name ORDER BY 5 DESC;
```

- `type=2` 是消费日志，`type=5` 是错误日志，**不要混在一起算成功率**。
- 逐日查询要 `ORDER BY d` 并对结果再排一次序：只含错误日志的日期不在第一条查询里，补插时会被追加到末尾。
- 空输出要标"无数据"，不要渲染成 0（0 和"没有记录"是两件事）。

### 2.5 主机流量（BandwagonHost/KiwiVM 类面板）

```python
url = "http://api.64clouds.com/v1/getLiveServiceInfo?veid=%s&api_key=%s" % (veid, key)
req = urllib.request.Request(url, headers={"User-Agent": "curl/8.0"})   # ← 必须
```

实测两个坑：

1. **HTTPS 会被 Cloudflare 拦成 403**，用 HTTP 可以。
2. **Python 默认 UA（`Python-urllib/3.x`）也被拦**，必须伪装成 curl/浏览器。
3. `getLiveServiceInfo` 可能不返回 `next_due_date`，续费日要么回落到 `getServiceInfo`，要么直接以面板为准。
4. 单位：`plan_monthly_data` 是字节，1000 GiB 常被面板显示成 "1073.7 GB"。写文档时标清楚 GiB/GB。

外部 HTTP 依赖建议**加文件缓存（10 分钟）+ 失败回退旧值并标记 stale**，不要让它成为面板的可用性瓶颈。

---

## 3. 第二层：DSH Desktop 客户端插件

> 这一节是本文的核心。如果你按其它教程装插件，很可能遇到"插件明明装了，设置里却没有，也没有任何报错"——原因在 3.2。

### 3.1 加载机制（够用的理解）

DSH 启动时：

1. 扫描**已启用的 Loader 配置项**（也就是组合树里的行）；
2. 对每个行取 `package.json`，看 `dsh.client.platform === "web"`；
3. 解析 `exports["./client"]` 指向的**已构建 bundle 文件**；
4. 计算内容哈希写进启动图，并通过 `/plugins/<包名>/client.js` 提供该文件；
5. 浏览器执行 bundle 只做一件事：`window.__ModuleLoader__.load({ id, factory })` 注册工厂，模块副作用（含 CSS 注入）在物化时运行。

### 3.2 静默失败：三道门禁必须同时成立

扫描逻辑里这一段是关键：

```js
resolveMeta(pkgName) {
  try { pkgPath = require.resolve(`${pkgName}/package.json`) }
  catch { return null }        // ← 什么也不报，直接当这个包不存在
  ...
}
```

所以**"解析不到包"是静默的**：不抛错、不写日志、不出现在设置里。相比之下，另两种失败会大声报错（`declares dsh.client but exports no "./client" bundle`、`MissingClientBundleError`）。**如果日志里没有任何报错，优先怀疑门禁 B。**

| 门禁 | 要求 | 怎么验 |
| --- | --- | --- |
| A | 组合树里有这一行，且 fiber 已激活、未 disabled | `dsh --profile <p> --dump-config` 里能找到你的 `id` |
| B | 从 **profile 目录**能 `require.resolve('<包名>/package.json')` | `createRequire(<profile>/package.json).resolve(...)` |
| C | `dsh.client.platform === "web"` 且 `exports["./client"]` 的**文件真实存在** | 文件存在性检查 + bundle 里有 `__ModuleLoader__.load` |

宿主侧还有一条隐含要求：**Host 半必须能正常 `apply()` 并激活**，否则 `entry.fiber === undefined`，扫描直接跳过。

### 3.3 包结构

```
your-plugin/
├── package.json
└── lib/
    ├── index.js     # Host 半：export function apply() {}
    └── client.js    # 浏览器 bundle（第 3.4 节格式）
```

`package.json` 关键字段：

```json
{
  "name": "your-plugin",
  "type": "module",
  "main": "lib/index.js",
  "exports": {
    ".": "./lib/index.js",
    "./client": "./lib/client.js",
    "./package.json": "./package.json"
  },
  "dsh": { "client": { "platform": "web" } }
}
```

- `name` 必须与安装名、patch 行里的 `name` 完全一致。
- `./package.json` 这一条要留：解析逻辑会去读它。
- 不需要 `dsh.bundle`（那是"提供配置补丁的 bundle 层"才用的，普通插件会看到一条 `declares no dsh.bundle` 警告，属正常）。

### 3.4 bundle 格式与 require 白名单

**手写 bundle 是合法的**，不必用构建流水线。格式固定：

```js
window.__ModuleLoader__.load({
  id: "your-plugin",                    // 与包名一致
  factory: (require) => {
    var module = { exports: {} }
    var exports = module.exports
    const React = require("react")
    const h = React.createElement
    function Component() { return h("div", null, "hello") }
    function apply(ctx) {
      ctx.slots.inject("settings.section", () => ctx.slots.register({
        name: "settings.section", id: "your-plugin", order: 95,
        label: "我的面板", inject: () => ({}),
      }, Component))
    }
    exports.apply = apply
    exports.inject = ["slots"]
    return module.exports
  }
})
```

**`require()` 只能用平台种子词**：`react`、`react/jsx-runtime`，以及外壳提供的少量 `@deepseek-ai/dsh-client-*`。require 其它模块会抛：

```
require("x") missed the module table — ... (a build-time externals drift)
```

**不要用 JSX/TS**：没有编译步骤，直接写 `React.createElement`。

### 3.5 可以把面板放哪几个座位

| Slot | 形态 | 适用 |
| --- | --- | --- |
| `settings.section` | 设置里一页 | 含敏感信息（完整 Key）的深度查看页 |
| `conversation.view` | 会话顶部标签页（整页） | 主看板，和"对话/轨迹"并列 |
| `conversation.input.dock` | 输入框上方一条 | 极简摘要（不要塞内容，会挡输入） |
| `shell.overlay` | 浮层 | 慎用：只适合 badge/提示，放面板要自己处理指针事件和定位 |

先 `ctx.get("slots")` 拿到服务，用 `slots.inject(name, () => slots.register(...))` 注册。**不要假设 `window`/`document` 全局可用**，需要时用 `typeof document !== "undefined"` 兜。

### 3.6 安装（官方通道）

```bash
# 1) 把包放进你的源码目录（不要直接改 node_modules）
~/.dsh/plugins/your-plugin/

# 2) 用官方命令装进 profile（内部转发给 pnpm）
DSH_BIN="/Applications/DSH Desktop.app/Contents/Resources/app.asar.unpacked/node_modules/@deepseek-ai/dsh/lib/bin.js"
node "$DSH_BIN" plugin --profile desktop add file:../../plugins/your-plugin

# 3) 在 profile 的 cordis.patch.yml 里加一行（顶层数组，insert 不带 id = 追加到根）
cat >> ~/.dsh/profiles/desktop/cordis.patch.yml <<'YAML'
- insert:
    - id: your-plugin
      name: your-plugin
YAML
```

两处易错：

- patch 文件原本是 `[]` 时，**必须替换掉 `[]` 再追加**，不能直接往后面贴（会变成两个 YAML 文档）。
- 手工建 `node_modules` 软链会被 DSH 启动时的依赖重整冲掉；**声明成 profile 依赖**（`dsh plugin add` 会写进 profile 的 `package.json`）才是持久的。

### 3.7 免重启验证：`--dump-config`

```bash
node "$DSH_BIN" --profile desktop --dump-config | grep -A1 your-plugin
```

能打印出你那一行，说明门禁 A 成立。这一步不需要重启 DSH，是排障时最省时间的动作。

> `--dump-config` 会**写** profile 的 `cordis.yml`（准备步骤），在无写权限的环境里会 `EPERM`，属预期。

### 3.8 必须重启，且没有热更新

静态插件的 client bundle 只在**启动/激活时**读一次并算哈希。**每改一次 `client.js` 都要重启 DSH Desktop。**

所以正确节奏是：先在离线环境把渲染跑通，再重启验证。最小离线验证：

```bash
node scripts/dsh-preflight.mjs ~/.dsh/plugins/your-plugin      # 门禁 + bundle 形状
```

### 3.9 观测插件有没有被加载

- **设置 → 插件清单**（DSH 自带页）读的是 Loader 的真实清单，是"有没有加载"最可靠的观测点。
- 日志里没有报错**不能**证明加载成功（静默失败就是没报错）。

---

## 4. 常见陷阱（实测）

| # | 现象 | 真因 | 处置 |
| --- | --- | --- | --- |
| 4.1 | 插件装了但设置里没有，日志干净 | 门禁 B：包解析不到（静默 null） | 从 profile 目录 `require.resolve` 验证 |
| 4.2 | `missed the module table` | bundle 里 require 了非种子模块 | 只用 `react` |
| 4.3 | 面板一直转圈/报错 | 接口域名解析到旧 IP | 换 IP 后必须同步改 DNS 记录 |
| 4.4 | 换 IP 后一切正常但面板空 | **只改了服务器，忘了改 DNS**（云上灰云记录不会自动跟随） | 改 A 记录并等 TTL；`dig @公共DNS` 复核 |
| 4.5 | 本机测什么都是"通" | 本机 TUN/代理会**接受所有连接**（TCP 0.00 秒即成功），TLS 才失败 | 绑定物理网卡再测：`curl --interface en0 --resolve host:port:IP` |
| 4.6 | 面板显示的费用比实际大 3 个数量级 | 已经折算过的美元又除了一次 500000 | 见 2.3 |
| 4.7 | 主机 API 一直 403 | Cloudflare 拦 HTTPS，且拦 Python 默认 UA | HTTP + curl UA |
| 4.8 | 证书没问题但域名连不上 | 换 IP 后证书与域名不匹配 | `openssl s_client -servername` 核对 |

---

## 5. 第三层：告警（离线也能收到）

面板要有人打开才看得到；真正需要"出问题主动告诉你"的部分放服务器上。

### 5.1 规则设计

- **分级**：P0 立即通知（服务挂、通道断、流量 ≥95%、实例被暂停）、P1 当日汇总（流量 ≥80%、证书/续费 ≤30 天）、P2 写时间线。
- **去重**：同一个 key 30 分钟内只发一次，恢复时补一条恢复通知。
- **文案必须带证据**：采样次数、中位值、最大值，不要只写一个瞬时读数。

### 5.2 性能指标必须多次采样取中位

同一节点相隔十几分钟两次测上传，可能一次 91 KB/s、一次 676 KB/s。**单次读数会误判**。

强制要求：

1. 任何性能指标**至少连续采样 5 次，取中位数**；
2. 单次异常值不得触发告警，需**连续 3 次越界**；
3. 告警文案写明"采样 5 次 / 中位 X / 最大 Y"。

### 5.3 必须监控的两类"假正常"

- **服务状态假正常**：某些隧道服务 `systemctl is-active` 显示 active，实际 `wg show` 的 `received = 0`。必须看字节数。
- **连通性假正常**：TCP 连通不代表能用。大请求体上传慢照样会让客户端超时，所以**上传速度要单独监控**。

### 5.4 国内视角

可用性与性能必须从**客户端一侧**（国内）测，服务器测不出自己入站线路的质量。探针脚本要：

- 绑物理网卡绕开本机 TUN（macOS `setsockopt(IPPROTO_IP, 25, if_nametoindex("en0"))`，Linux `SO_BINDTODEVICE`）；
- 报告里把"家里基线"和"办公实况"分开写。

---

## 6. 验收清单

- [ ] `dsh --profile <p> --dump-config` 里能看到插件行
- [ ] 设置 → 插件清单里有该插件
- [ ] 面板能显示真实数据（不是 0、不是占位）
- [ ] 改一次 `client.js` 后重启，构建戳变化（证明加载的是新文件）
- [ ] 关掉网关数据接口的令牌，前端显示明确错误（而不是空白）
- [ ] 回滚脚本可执行，回滚后插件消失
- [ ] 告警脚本 `--dry-run` 能打印将要发送的内容
- [ ] 面板上的数字与数据库 `systemctl` / SQL 直读一致（抽检 3 项）
