#!/usr/bin/env python3
"""拉取订阅 API 网关的只读统计快照（智脑管理中心 / 看板用）。

零依赖，Python 3.8+。

用法:
  # 凭据走环境变量（推荐）
  export AIGW_BASIC_USER=admin
  export AIGW_BASIC_PASS='...'
  ./stats-client.py                 # 打印中文摘要
  ./stats-client.py --json          # 输出原始 JSON
  ./stats-client.py --out stats.json  # 写入文件（供程序消费）
  ./stats-client.py --watch 300     # 每 300 秒刷新摘要

  # 或直接传参（注意会进 shell 历史）
  ./stats-client.py --user admin --password '...'

端点: GET /stats/gateway-stats.json （HTTP Basic Auth，与网关面板同一套凭据）
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.request

DEFAULT_URL = "https://aigateway.evenbetter.tech:8443/stats/gateway-stats.json"


def fetch(url: str, user: str, password: str, timeout: int = 45, insecure: bool = False) -> dict:
    token = base64.b64encode(f"{user}:{password}".encode()).decode()
    req = urllib.request.Request(url, headers={"Authorization": "Basic " + token,
                                               "Accept": "application/json"})
    ctx = ssl.create_default_context()
    if insecure:
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx))
    with opener.open(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def render(d: dict) -> str:
    out = []
    gen = d.get("generated_at", "?")
    out.append(f"网关统计  ({gen})")
    out.append("=" * 52)

    gw = d.get("gateway", {})
    out.append(f"渠道 {gw.get('channel_count', 0)} 个 / 模型 {gw.get('total_models', 0)} 个")
    for ch in gw.get("channels", []):
        state = "启用" if ch.get("status") == 1 else f"停用({ch.get('status')})"
        out.append(f"  - {ch.get('name')}  模型 {ch.get('model_count')}  {state}")

    s = d.get("summary_24h", {})
    if s:
        out.append("")
        out.append("近 24 小时")
        out.append(f"  成功 {s.get('success_requests', 0)} 次 / 失败 {s.get('error_requests', 0)} 次"
                   f" / 疑似空响应 {d.get('suspected_empty_responses_24h', 0)} 次")
        out.append(f"  token 输入 {s.get('prompt_tokens', 0):,} / 输出 {s.get('completion_tokens', 0):,}"
                   f"  平均延迟 {s.get('avg_latency_s', 0)}s")

    models = d.get("usage_by_model_24h") or []
    if models:
        out.append("")
        out.append("按模型（近 24h）")
        for m in models:
            out.append(f"  {m.get('model', '?'):<22} {m.get('requests', 0):>5} 次  "
                       f"均 {m.get('avg_latency_s', 0):>6}s  峰 {m.get('max_latency_s', 0):>6}s")

    users = d.get("usage_by_user") or []
    if users:
        out.append("")
        out.append("按用户（累计）")
        for u in users:
            out.append(f"  {str(u.get('display_name', '?'))[:16]:<18} 请求 {u.get('requests', 0):>6}  "
                       f"已用 {u.get('used_usd', 0):>12,.2f}")

    mon = d.get("monitor") or {}
    out.append("")
    out.append(f"巡检: {mon.get('state', 'unknown')}  ({mon.get('checked_at', '?')})  {mon.get('detail', '')}")

    errs = d.get("recent_errors") or []
    if errs:
        out.append("")
        out.append(f"最近错误 {len(errs)} 条（显示前 5）")
        for e in errs[:5]:
            out.append(f"  {e.get('at')}  {e.get('user')}  {e.get('model')}  {str(e.get('detail'))[:60]}")
    return "\n".join(out)


def main() -> int:
    ap = argparse.ArgumentParser(description="拉取订阅 API 网关统计快照")
    ap.add_argument("--url", default=os.environ.get("AIGW_STATS_URL", DEFAULT_URL))
    ap.add_argument("--user", default=os.environ.get("AIGW_BASIC_USER", ""))
    ap.add_argument("--password", default=os.environ.get("AIGW_BASIC_PASS", ""))
    ap.add_argument("--json", action="store_true", help="输出原始 JSON")
    ap.add_argument("--out", help="把原始 JSON 写入该文件")
    ap.add_argument("--watch", type=int, metavar="SEC", help="每 SEC 秒刷新一次摘要")
    ap.add_argument("--insecure", action="store_true", help="跳过 TLS 证书校验（不推荐）")
    args = ap.parse_args()

    if not args.user or not args.password:
        print("缺少凭据：请设置 AIGW_BASIC_USER / AIGW_BASIC_PASS，或使用 --user/--password", file=sys.stderr)
        return 2

    while True:
        try:
            d = fetch(args.url, args.user, args.password, insecure=args.insecure)
        except urllib.error.HTTPError as e:
            print(f"HTTP {e.code}: {e.reason}", file=sys.stderr)
            return 1
        except Exception as e:
            print(f"请求失败: {e}", file=sys.stderr)
            return 1

        if args.out:
            with open(args.out, "w", encoding="utf-8") as f:
                json.dump(d, f, ensure_ascii=False, indent=1)
            print(f"已写入 {args.out}（{os.path.getsize(args.out)} 字节）")
        elif args.json:
            print(json.dumps(d, ensure_ascii=False, indent=1))
        else:
            print(render(d))

        if not args.watch:
            return 0
        time.sleep(args.watch)


if __name__ == "__main__":
    raise SystemExit(main())
