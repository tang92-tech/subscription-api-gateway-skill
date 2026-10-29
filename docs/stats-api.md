# 网关统计接口（只读）

供企业智脑管理中心 / 内部看板拉取网关运行数据。**只读，不提供任何写操作。**

## 端点

```
GET https://<gateway-host>:8443/stats/gateway-stats.json
Authorization: Basic <base64(user:password)>
```

- 鉴权沿用**网关面板的同一套 Basic Auth**（`/stats/` 路径刻意不加入 `/api|/v1` 的免认证豁免列表）。
- 响应 `application/json`，`Cache-Control: no-store`。
- 快照由服务端 cron **每 5 分钟**重新生成；`generated_at` 是快照时间，不是请求时间。

## 响应结构

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `generated_at` / `generated_at_epoch` | string / int | 快照生成时间 |
| `gateway.channel_count` / `gateway.total_models` | int | 渠道数 / 对外模型总数 |
| `gateway.channels[]` | array | 每渠道：`id` `name` `status`(1=启用) `model_count` `models[]` `group` `used_usd` |
| `usage_by_user[]` | array | 每位用户：`user_id` `username` `display_name` `requests` `used_usd` `remaining_usd` |
| `usage_by_model_24h[]` / `usage_by_model_7d[]` | array | 每模型：`model` `requests` `prompt_tokens` `completion_tokens` `used_usd` `avg_latency_s` `max_latency_s` |
| `usage_by_channel_24h[]` | array | 每渠道近 24h：`channel` `requests` `avg_latency_s` |
| `summary_24h` | object | 近 24h：`success_requests` `error_requests` `prompt_tokens` `completion_tokens` `used_usd` `avg_latency_s` |
| `suspected_empty_responses_24h` | int | **"假成功"**数量：上游超时但仍返回 200、无 usage 的请求（详见部署台账第 45 条） |
| `recent_errors[]` | array | 近 24h 失败（最多 30 条）：`at` `user` `token` `model` `detail` |
| `monitor` | object | 服务端巡检结果：`checked_at` `state` `detail` |

### 两个必须理解的单位

1. **`used_usd` / `remaining_usd` 是 New API 的"额度"折算值，不等于真实金钱。** 订阅转发场景下实际成本为 0，这些数字只是计数器，用于观察相对消耗速度（部署台账第 47 条）。
2. **`suspected_empty_responses_24h` 必须单独看。** 这类请求在 `summary_24h.success_requests` 里被计为成功，但客户端实际拿到的是空输出，属于"假成功"。

## 客户端 `scripts/stats-client.py`

零依赖，Python 3.8+。

```bash
export AIGW_BASIC_USER=admin
export AIGW_BASIC_PASS='面板 Basic Auth 密码'

./scripts/stats-client.py                  # 中文摘要
./scripts/stats-client.py --json           # 原始 JSON
./scripts/stats-client.py --out stats.json # 写文件，供程序消费
./scripts/stats-client.py --watch 300      # 每 5 分钟刷新
```

可选环境变量：`AIGW_STATS_URL` 覆盖默认端点。

退出码：`0` 成功，`1` 请求失败，`2` 缺凭据。

## 接入企业智脑（两种方式）

### 方式一：MCP 工具（推荐，智脑已有 MCP 服务）

在智脑的 MCP 服务里加一个只读工具，例如：

```python
@mcp.tool()
def get_gateway_stats(scope: str = "summary") -> dict:
    """拉取订阅 API 网关的实时统计（只读）。scope: summary|users|models|errors|full"""
    d = stats_client.fetch(URL, USER, PASS)
    if scope == "full":
        return d
    if scope == "users":
        return {"generated_at": d["generated_at"], "usage_by_user": d["usage_by_user"]}
    if scope == "models":
        return {"generated_at": d["generated_at"], "usage_by_model_24h": d["usage_by_model_24h"]}
    if scope == "errors":
        return {"generated_at": d["generated_at"], "recent_errors": d["recent_errors"],
                "suspected_empty_responses_24h": d["suspected_empty_responses_24h"]}
    return {"generated_at": d["generated_at"], "summary_24h": d["summary_24h"], "monitor": d["monitor"]}
```

关键点：**凭据只放在智脑服务的环境变量里**，不要进入工具参数或模型可见的输入输出。

### 方式二：网页看板

智脑管理中心后端定时调用 `stats-client.py --out`，前端读取该 JSON 渲染表格/图表即可。不需要在前端保存任何凭据。

## 安全边界

- 接口**只读**：底层使用 SQLite 只读连接（`mode=ro`），不写任何表。
- 不含任何密钥、令牌明文或用户密码；`usage_by_user` 只有用户名、请求数、额度。
- 端点受面板 Basic Auth 保护；**不要把 Basic Auth 凭据放进前端代码或仓库**。
- 若需要给第三方仪表盘临时访问，建议在 nginx 上单独开一个受限的 `location` 与独立凭据，而不是共享面板凭据。
