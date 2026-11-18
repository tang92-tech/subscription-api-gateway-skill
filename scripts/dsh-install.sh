#!/usr/bin/env bash
# DSH Desktop 客户端插件 · 安装（幂等，可重复执行）
#
# 用法：
#   bash dsh-install.sh <插件源码目录> [插件名] [profile 名]
# 例：
#   bash dsh-install.sh ~/.dsh/plugins/your-plugin your-plugin desktop
#
# 做四件事：备份 → 同步源码 → 官方通道装进 profile → 写 patch 行 → dump-config 验证
# 不做：改 DSH 本体、改 nginx、改网关
set -euo pipefail

SRC="${1:?用法: dsh-install.sh <插件源码目录> [插件名] [profile 名]}"
PKG="${2:-$(basename "$SRC")}"
PROFILE_NAME="${3:-desktop}"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
PROFILE="$DSH_HOME/profiles/$PROFILE_NAME"
PLUGINS="$DSH_HOME/plugins"
APP="/Applications/DSH Desktop.app/Contents/Resources/app.asar.unpacked"
DSH_BIN="$APP/node_modules/@deepseek-ai/dsh/lib/bin.js"
TS="$(date +%Y%m%d-%H%M%S)"
BK="$DSH_HOME/backups/dsh-plugin-$PKG-$TS"

die() { echo "ERROR: $*" >&2; exit 1; }

[ -d "$PROFILE" ] || die "找不到 profile: $PROFILE"
[ -f "$SRC/package.json" ] || die "找不到源码: $SRC/package.json"
[ -f "$DSH_BIN" ] || die "找不到 dsh CLI: $DSH_BIN（用 DSH_APP 改路径请自行改脚本）"

echo "=== [1/5] 备份 ==="
mkdir -p "$BK/profile"
for f in cordis.yml cordis.patch.yml package.json pnpm-lock.yaml pnpm-workspace.yaml; do
  [ -f "$PROFILE/$f" ] && cp "$PROFILE/$f" "$BK/profile/$f"
done
[ -d "$PLUGINS/$PKG" ] && cp -a "$PLUGINS/$PKG" "$BK/source-before" || true
echo "备份: $BK"

echo "=== [2/5] 同步源码 ==="
mkdir -p "$PLUGINS/$PKG"
if [ "$(cd "$SRC" && pwd)" != "$(cd "$PLUGINS/$PKG" 2>/dev/null && pwd || echo x)" ]; then
  cp -a "$SRC"/. "$PLUGINS/$PKG"/
fi
ls -1 "$PLUGINS/$PKG"

echo "=== [3/5] 装进 profile（官方通道） ==="
if ( cd "$PROFILE" && node "$DSH_BIN" plugin --profile "$PROFILE_NAME" add "file:../../plugins/$PKG" ); then
  echo "安装完成"
else
  die "dsh plugin add 失败；先看输出里的 pnpm 报错"
fi

echo "=== [4/5] 写 patch 行 ==="
python3 - "$PROFILE/cordis.patch.yml" "$PKG" <<'PY'
import sys
path, pkg = sys.argv[1], sys.argv[2]
try:
    lines = open(path, encoding="utf-8").read().splitlines()
except FileNotFoundError:
    lines = []
if any(l.strip().startswith("- id: " + pkg) for l in lines):
    print("patch 行已存在，跳过")
    sys.exit(0)
kept = [l for l in lines if l.strip() != "[]"]      # 必须替换掉空的 [] 列表
while kept and kept[-1].strip() == "":
    kept.pop()
kept += ["- insert:", "    - id: " + pkg, "      name: " + pkg]
open(path, "w", encoding="utf-8").write("\n".join(kept) + "\n")
print("patch 行已写入")
PY
cat "$PROFILE/cordis.patch.yml"

echo "=== [5/5] 验证 ==="
( cd /tmp && node "$DSH_BIN" --profile "$PROFILE_NAME" --dump-config > /tmp/dsh-dump-$PKG.yml 2>/tmp/dsh-dump-$PKG.err ) \
  || echo "dump-config 失败（stderr 见 /tmp/dsh-dump-$PKG.err）"
if grep -q -- "$PKG" /tmp/dsh-dump-$PKG.yml 2>/dev/null; then
  echo "PASS 组合里出现 $PKG"
else
  echo "WARN 组合里没找到 $PKG，检查 patch 形状"
fi

echo
echo "=== 完成 ==="
echo "下一步必须重启 DSH Desktop（client bundle 只在启动时读取）"
echo "回滚: bash $PLUGINS/$PKG/../dsh-rollback.sh 或本仓库 scripts/dsh-rollback.sh $PKG"
