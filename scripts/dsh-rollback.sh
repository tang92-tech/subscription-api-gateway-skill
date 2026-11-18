#!/usr/bin/env bash
# DSH Desktop 客户端插件 · 回滚（一条命令）
#
# 用法：bash dsh-rollback.sh <插件名> [profile 名] [备份目录]
#   备份目录省略时，自动取 ~/.dsh/backups/ 下该插件最新的一份
#
# 还原 profile 的 cordis.yml / cordis.patch.yml / package.json / pnpm-lock.yaml，
# 并从 node_modules 移除包副本。源码保留在 ~/.dsh/plugins/ 不删除。
set -euo pipefail

PKG="${1:?用法: dsh-rollback.sh <插件名> [profile 名] [备份目录]}"
PROFILE_NAME="${2:-desktop}"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
PROFILE="$DSH_HOME/profiles/$PROFILE_NAME"

if [ "${3:-}" != "" ]; then
  BK="$3"
else
  BK="$(ls -d "$DSH_HOME"/backups/dsh-plugin-"$PKG"-* 2>/dev/null | sort | tail -1 || true)"
fi

if [ -z "${BK:-}" ] || [ ! -d "$BK" ]; then
  echo "找不到备份目录，为安全起见不做任何修改" >&2
  echo "可用备份：$(ls -d "$DSH_HOME"/backups/dsh-plugin-* 2>/dev/null | tail -3 | tr '\n' ' ')" >&2
  exit 1
fi

echo "=== 从备份还原: $BK ==="
for f in cordis.yml cordis.patch.yml package.json pnpm-lock.yaml pnpm-workspace.yaml; do
  if [ -f "$BK/profile/$f" ]; then
    cp "$BK/profile/$f" "$PROFILE/$f"
    echo "  还原 $f"
  fi
done
rm -rf "$PROFILE/node_modules/$PKG"
echo "  移除 $PROFILE/node_modules/$PKG"
echo
echo "已回滚。源码仍在 $DSH_HOME/plugins/$PKG（未删除）"
echo "请重启 DSH Desktop 让改动生效。"
