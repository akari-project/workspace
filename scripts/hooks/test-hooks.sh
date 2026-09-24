#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Claude Code hooks 的自动化测试（spec/43 43.3，M0-08 验收 1）：
# guard-paths.sh 拒绝生成代码、已提交迁移与密钥文件；post-edit.sh 编辑 Go 文件后自动格式化。
# 用法：scripts/hooks/test-hooks.sh（可从任意目录执行）。有失败时退出码为 1。
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
guard="$here/guard-paths.sh"
post="$here/post-edit.sh"

# 依赖缺失时报错，不静默跳过。
for bin in jq gofmt git; do
  if ! command -v "$bin" >/dev/null; then
    echo "test-hooks: 缺少 $bin，无法运行 hook 测试" >&2; exit 1
  fi
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "ok   $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1${2:+：$2}"; }

# 以 JSON 调用 hook：run <hook> <json>，结果写入 $code 与 $err。
run() {
  err="$(printf '%s' "$2" | "$1" 2>&1 >/dev/null)"; code=$?
}
json() { jq -cn --arg k "$1" --arg v "$2" '{tool_input: {($k): $v}}'; }

# guard-paths.sh 应拒绝：退出码 2 且 stderr 非空。
expect_deny() {
  run "$guard" "$(json "${2:-file_path}" "$1")"
  if [ "$code" = 2 ] && [ -n "$err" ]; then ok "guard 拒绝 $1"
  else bad "guard 拒绝 $1" "exit=$code stderr=${err:-<空>}"; fi
}
# guard-paths.sh 应允许：退出码 0。
expect_allow() {
  run "$guard" "$(json "${2:-file_path}" "$1")"
  if [ "$code" = 0 ]; then ok "guard 允许 $1"
  else bad "guard 允许 $1" "exit=$code stderr=$err"; fi
}

# --- guard-paths.sh：生成代码 ---
expect_deny "$tmp/panel-spec/gen/go/node/v1/envelope.pb.go"
expect_deny "$tmp/panel-spec/gen/ts/client.d.ts"
expect_deny "$tmp/panel/server/internal/app/wire_gen.go"
expect_deny "$tmp/panel/server/internal/api/api.pb.go"
expect_deny "$tmp/panel/web/sdk/src/client.gen.ts"
expect_deny "$tmp/panel/server/internal/db/sqlc/models.go"

# --- guard-paths.sh：密钥文件 ---
expect_deny "$tmp/panel/.env"
expect_deny "$tmp/panel/.env.local"
expect_deny "$tmp/panel/secrets/x"

# --- guard-paths.sh：普通文件与输入形式 ---
expect_allow "$tmp/panel/server/internal/app/app.go"
expect_allow "spec/README.md"
run "$guard" '{"tool_input":{}}'
if [ "$code" = 0 ]; then ok "guard 允许无 file_path 的输入"; else bad "guard 允许无 file_path 的输入" "exit=$code"; fi
expect_deny "$tmp/panel-spec/gen/go/x.pb.go" path   # 使用 path 键同样识别

# --- guard-paths.sh：迁移 ---
repo="$tmp/repo"
g() { git -C "$repo" -c user.name=hook-test -c user.email=hook-test@example.invalid -c commit.gpgsign=false "$@"; }
mkdir -p "$repo/server/migrations"
git init -q "$repo"
echo "-- 初始迁移" > "$repo/server/migrations/00001_init.sql"
g add server/migrations/00001_init.sql && g commit -q -m init
echo "-- 新迁移" > "$repo/server/migrations/00002_x.sql"
expect_deny  "$repo/server/migrations/00001_init.sql"
expect_allow "$repo/server/migrations/00002_x.sql"
export ALLOW_MIGRATION_EDIT=1
expect_allow "$repo/server/migrations/00001_init.sql"
unset ALLOW_MIGRATION_EDIT

# --- post-edit.sh：Go 文件自动格式化 ---
src="$tmp/fmt/x.go"
mkdir -p "$(dirname "$src")"
printf 'package x\nfunc  F( ) {\nreturn}\n' > "$src"
want="$(gofmt < "$src")"
run "$post" "$(json file_path "$src")"
if [ "$code" = 0 ] && [ "$(cat "$src")" = "$want" ] && [ -z "$(gofmt -l "$src")" ]; then
  ok "post-edit 格式化 Go 文件"
else
  bad "post-edit 格式化 Go 文件" "exit=$code stderr=$err 内容=$(cat "$src")"
fi

# --- post-edit.sh：不存在的文件与非 Go 文件不报错 ---
run "$post" "$(json file_path "$tmp/nope/missing.go")"
if [ "$code" = 0 ] && [ -z "$err" ]; then ok "post-edit 忽略不存在的文件"; else bad "post-edit 忽略不存在的文件" "exit=$code stderr=$err"; fi
printf 'hello  \n' > "$tmp/fmt/notes.md"
run "$post" "$(json file_path "$tmp/fmt/notes.md")"
if [ "$code" = 0 ] && [ -z "$err" ] && [ "$(cat "$tmp/fmt/notes.md")" = "hello  " ]; then
  ok "post-edit 忽略非 Go 文件"
else
  bad "post-edit 忽略非 Go 文件" "exit=$code stderr=$err"
fi

echo "test-hooks: $pass 通过，$fail 失败"
[ "$fail" = 0 ]
