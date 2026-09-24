#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# 用法：scripts/clone-all.sh <github-org>
# 得到与 scripts/bootstrap.sh 相同的布局：
#   - 各仓库的 origin 指向 <org>；node-agent 另有 upstream（cedar2025/Xboard-Node）；
#   - sing-box、xray-core 检出 panel-base（node-agent/go.mod 的 replace 所指提交），
#     另有 xboard-fork（Xboard-Node 作者的 fork，只取提交不取文件内容）与 official（官方上游）。
# 已存在的目录不重新克隆，只补齐远端。
set -euo pipefail
org="${1:?github org required}"
cd "$(dirname "$0")/.."

ensure_remote() { # dir name url [partial]
  if ! git -C "$1" remote get-url "$2" >/dev/null 2>&1; then
    git -C "$1" remote add "$2" "$3"
    if [ "${4:-}" = partial ]; then
      git -C "$1" config "remote.$2.promisor" true
      git -C "$1" config "remote.$2.partialclonefilter" blob:none
    fi
  fi
}

# node-agent 为本组织从 cedar2025/Xboard-Node fork 的仓库
for repo in panel-spec panel node-agent sing-box xray-core client; do
  if [ ! -d "$repo" ]; then
    case "$repo" in
      sing-box|xray-core) branch=(--branch panel-base) ;;
      *) branch=() ;;
    esac
    git clone "${branch[@]}" "git@github.com:${org}/${repo}.git" "$repo" || { echo "skip ${repo}"; continue; }
  fi
  case "$repo" in
    node-agent)
      ensure_remote "$repo" upstream https://github.com/cedar2025/Xboard-Node.git ;;
    sing-box)
      ensure_remote "$repo" xboard-fork https://github.com/cedar2025/sing-box.git partial
      ensure_remote "$repo" official https://github.com/SagerNet/sing-box.git ;;
    xray-core)
      ensure_remote "$repo" xboard-fork https://github.com/cedar2025/Xray-core.git partial
      ensure_remote "$repo" official https://github.com/XTLS/Xray-core.git ;;
  esac
done
[ -f go.work ] || cp go.work.example go.work
