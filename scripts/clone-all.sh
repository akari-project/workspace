#!/usr/bin/env bash
# 用法：scripts/clone-all.sh <github-org>
set -euo pipefail
org="${1:?github org required}"
cd "$(dirname "$0")/.."
# node-agent 为本组织从 cedar2025/Xboard-Node fork 的仓库
for repo in panel-spec panel node-agent sing-box xray-core client; do
  if [ ! -d "$repo" ]; then
    git clone "git@github.com:${org}/${repo}.git" "$repo" || echo "skip ${repo}"
  fi
done
[ -f go.work ] || cp go.work.example go.work
