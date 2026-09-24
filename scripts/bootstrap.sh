#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# 首次在本地建立工作区（解压起步包后运行一次）：
#   1. 为 workspace 与 panel-spec、panel、client 初始化独立的 git 仓库；
#   2. 把 node-agent 种子文件合入 cedar2025/Xboard-Node 的克隆；
#   3. 按 Xboard-Node go.mod 的 replace 克隆 sing-box 与 Xray-core 的 fork 到锁定提交。
# 用法：scripts/bootstrap.sh [--org <GitHub 组织>] [--skip-forks]
#   --org        为各仓库设置 origin 远端（git@github.com:<组织>/<仓库>.git），之后可直接 push
#   --skip-forks 暂不克隆两个内核 fork（体积较大，可稍后再运行本脚本）
set -euo pipefail
cd "$(dirname "$0")/.."
WS="$(pwd)"
ORG=""; SKIP_FORKS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --org) ORG="${2:?}"; shift 2 ;;
    --skip-forks) SKIP_FORKS=1; shift ;;
    *) echo "未知参数：$1" >&2; exit 1 ;;
  esac
done
XBN_URL="https://github.com/cedar2025/Xboard-Node.git"
say() { printf '\033[1m==> %s\033[0m\n' "$*"; }

git config user.email >/dev/null || { echo "请先设置 git user.name 与 user.email" >&2; exit 1; }

set_origin() { # dir repo
  [ -n "$ORG" ] || return 0
  git -C "$1" remote get-url origin >/dev/null 2>&1 && git -C "$1" remote set-url origin "git@github.com:${ORG}/$2.git" \
    || git -C "$1" remote add origin "git@github.com:${ORG}/$2.git"
}

init_seed_repo() { # dir
  local d="$1"
  if [ -d "$d/.git" ]; then echo "  $d 已是 git 仓库，跳过"; return; fi
  git -C "$d" init -q -b main
  git -C "$d" add -A
  git -C "$d" commit -q --signoff -m "chore: seed from starter kit"
  set_origin "$d" "$d"
  echo "  $d 初始化完成"
}

say "workspace"
if [ ! -d .git ]; then
  git init -q -b main && git add -A && git commit -q --signoff -m "chore: seed from starter kit"
fi
set_origin . workspace

say "panel-spec、panel、client"
for d in panel-spec panel client; do init_seed_repo "$d"; done

say "node-agent（fork 自 Xboard-Node）"
if [ ! -d node-agent/.git ]; then
  tmp="$(mktemp -d)"
  git clone -q "$XBN_URL" "$tmp/xbn"
  base="$(git -C "$tmp/xbn" rev-parse HEAD)"
  mv "$tmp/xbn/.git" node-agent/.git
  (cd "$tmp/xbn" && tar cf - .) | (cd node-agent && tar xkf - 2>/dev/null || true)   # 上游文件；-k 不覆盖种子文件
  rm -rf "$tmp"
  git -C node-agent remote rename origin upstream
  for f in FORK_PLAN.md UPSTREAM.md; do
    [ -f "node-agent/$f" ] || mv "node-agent/templates/$f" "node-agent/$f"
  done
  rmdir node-agent/templates 2>/dev/null || true
  sed -i.bak "s/<提交哈希>/${base}/" node-agent/UPSTREAM.md && rm -f node-agent/UPSTREAM.md.bak
  git -C node-agent add -A
  git -C node-agent add -f CLAUDE.md .claude FORK_PLAN.md UPSTREAM.md
  git -C node-agent commit -q --signoff -m "chore: add project CLAUDE.md, skills and fork plan"
  set_origin node-agent node-agent
  echo "  分叉基点 ${base}"
else
  echo "  node-agent 已是 git 仓库，跳过"
fi

if [ "$SKIP_FORKS" = 1 ]; then
  say "跳过内核 fork（--skip-forks）"
else
  say "内核 fork（按 node-agent/go.mod 的 replace 锁定提交）"
  clone_fork() { # module dir official
    local line target ver commit
    line="$(grep -E "^replace ${1} => " node-agent/go.mod || true)"
    if [ -z "$line" ]; then echo "  go.mod 中没有 ${1} 的 replace，跳过"; return; fi
    target="$(echo "$line" | awk '{print $4}')"; ver="$(echo "$line" | awk '{print $5}')"
    commit="${ver##*-}"
    if [ -d "$2/.git" ]; then echo "  $2 已存在，跳过"; return; fi
    git clone -q --filter=blob:none "https://${target}.git" "$2"
    git -C "$2" checkout -q -b panel-base "$commit"
    git -C "$2" remote rename origin xboard-fork
    git -C "$2" remote add official "$3"
    cp templates/fork-CLAUDE.md "$2/CLAUDE.md"; cp templates/PATCHES.md "$2/PATCHES.md"
    git -C "$2" add -f CLAUDE.md PATCHES.md
    git -C "$2" commit -q --signoff -m "chore: add CLAUDE.md and PATCHES.md"
    set_origin "$2" "$2"
    echo "  $2：${target} @ ${commit}（分支 panel-base）"
  }
  clone_fork github.com/sagernet/sing-box sing-box https://github.com/SagerNet/sing-box.git
  clone_fork github.com/xtls/xray-core xray-core https://github.com/XTLS/Xray-core.git
fi

say "完成"
cat << MSG
下一步：
  cd "$WS" && claude
  首条指令：阅读 CLAUDE.md 与 spec/README.md，用五句话复述项目目标、已定决策与 M0 顺序，不要修改文件。
$( [ -n "$ORG" ] && echo "推送：在 GitHub 组织 ${ORG} 下创建同名空仓库后，对每个目录执行 git -C <目录> push -u origin HEAD" )
MSG
