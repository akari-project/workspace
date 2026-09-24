<!-- SPDX-License-Identifier: Apache-2.0 -->

# workspace：开源 VPN 控制面板的开发工作区

最终目的：GO开发一个类似于传统 xboard v2board VPN商业面板      高性能  生产级   易维护    。

解压后的目录就是最终的本地布局：各代码仓库都在 `workspace/` 之下，从这里启动 Claude Code 即可访问全部仓库。

```
workspace/                  本仓库：规格、决策、任务、Claude Code 配置
├── CLAUDE.md               项目概要、已定决策、工作规则、完成的定义
├── spec/                   规格（唯一依据），从 spec/README.md 开始读
├── adr/  backlog/  workflows/  templates/
├── .claude/  .mcp.json  compose.dev.yaml  go.work.example
├── scripts/                bootstrap.sh、clone-all.sh、hooks、build-spec-page.py
├── panel-spec/             独立 git 仓库：proto 与 OpenAPI 草案
├── panel/                  独立 git 仓库：控制面种子（CLAUDE.md、Skills、初始迁移）
├── node-agent/             独立 git 仓库：bootstrap 后为 Xboard-Node 的克隆 + 本项目文件
├── sing-box/  xray-core/   独立 git 仓库：bootstrap 按 Xboard-Node 的 go.mod 克隆到锁定提交
└── client/                 独立 git 仓库：预留
```

子仓库被本仓库的 `.gitignore` 忽略，各自独立提交与推送。

## 开发者工具与版本

每位开发者需要安装：

| 工具 | 版本 | 用途 / 用在哪个仓库 | 版本来源 |
|---|---|---|---|
| Go | 1.26 以上；模块要求 `go 1.26.0`，工具链 `go1.27.1` | panel/server、panel-spec、node-agent；本机 1.26 以上即可，`GOTOOLCHAIN` 会自动下载 1.27.1 | panel/server/go.mod、panel-spec/go.mod 的 `go` 与 `toolchain` 行；`go.work.example` 写 `go 1.26` |
| Node.js | 22 LTS | panel/web（portal、admin、ui、sdk） | spec/41 41.2；panel/web/package.json `engines.node >=22`；CI `node-version: 22` |
| pnpm | 12.5.1 | panel/web；建议 `corepack enable`，按 `packageManager` 自动取用 | panel/web/package.json 的 `packageManager` |
| buf | 1.73.0 | panel-spec：`buf lint`、`buf breaking`、代码生成 | panel-spec CI 中 `bufbuild/buf-action` 的 `version` |
| Docker、Docker Compose v2 | 支持 `docker compose` 的版本 | `compose.dev.yaml`（postgres:18、valkey/valkey:9、axllent/mailpit）；panel 集成测试（testcontainers） | compose.dev.yaml |
| jq | 任意 | Claude Code hooks（`scripts/hooks/*.sh`） | scripts/hooks |
| git | 任意；已设置 `user.name` 与 `user.email` | 全部仓库；提交带 DCO 签名 | spec/42 42.6 |
| Python 3 | 3.x；CI 用 3.13 | workspace `make ci` 中的 `scripts/check_spdx.py` | workspace CI |
| Claude Code | 最新版 | 全部仓库；Agent Teams 由 `.claude/settings.json` 的 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` 开启 | spec/43 |

可选：

| 工具 | 用途 |
|---|---|
| goimports | post-edit hook 优先使用，缺少时退回 gofmt；`go install golang.org/x/tools/cmd/goimports@latest` |
| reuse | 本地运行 REUSE lint（CI 用 `fsfe/reuse-action`） |
| gopls、vtsls | LSP（spec/43 43.4），见下文“配置” |

由 Makefile 固定、无需手动安装（经 `go run` / `npx` 按版本拉取）：

- panel-spec：Redocly CLI 2.54.2、openapi-typescript 7.13.0、oasdiff v1.32.1、govulncheck v1.8.0、go-licenses v2.0.1；protoc-gen-go 由 `make tools` 安装，与 go.mod 中 `google.golang.org/protobuf` 同版本。
- panel：sqlc v1.31.1、staticcheck v0.8.1、govulncheck v1.8.0、go-licenses v2.0.1。前端 Mock 用的 Prism 在 panel/web 的 devDependencies 中，随 `pnpm install` 安装。

自检：

```bash
go version && node --version && pnpm --version && buf --version \
  && docker compose version && jq --version && python3 --version
```

修改 Claude Code hooks 后，在 workspace 运行 `make test-hooks`（已包含在 `make ci` 中）。

## 快速开始

先按上一节安装工具。

```bash
cd workspace
scripts/bootstrap.sh --org <你的 GitHub 组织>   # 不打算推送可省略 --org；内核 fork 较大，可加 --skip-forks 稍后再拉
claude
```

`bootstrap.sh` 做的事：
1. 为 workspace、panel-spec、panel、client 初始化 git 仓库并提交种子内容（带 DCO 签名）。
2. 克隆 cedar2025/Xboard-Node 到 `node-agent/`，保留其历史，原远端改名为 `upstream`，叠加本项目的 CLAUDE.md、Skills、FORK_PLAN.md、UPSTREAM.md（自动填入分叉基点）。
3. 读取 `node-agent/go.mod` 中的 `replace`，把 sing-box 与 Xray-core 的 fork 克隆到对应锁定提交，建立 `panel-base` 分支，远端为 `xboard-fork` 与 `official`。
4. 指定 `--org` 时为每个仓库设置 `origin`。在 GitHub 组织下创建同名空仓库后，`git -C <目录> push -u origin HEAD` 推送。

其他开发者之后只需克隆 `workspace` 并运行 `scripts/clone-all.sh <组织>`，得到同样的布局。

## 在 Claude Code 中

首条指令：

```
阅读 CLAUDE.md 与 spec/README.md，用五句话复述项目目标、已定决策与 M0 顺序，不要修改文件。
```

然后：
1. `按 workflows/spec-review.md 创建并运行 workflow。`（M0-01）
2. 处理评审报告中的严重问题，修改 spec 或写 ADR。
3. `执行 backlog/M0.md 的 M0-02。先列出涉及的规则编号与验收标准，给出计划，确认后实施。`

启动目录的选择（spec/43）：

| 任务 | 启动目录 |
|---|---|
| 跨仓功能、规格评审、发版审计、Agent Teams | `workspace/` |
| 单仓任务 | 该仓库目录，例如 `workspace/panel/` |
| 需要并行 worktree 的工作流 | 对应仓库目录（计费对抗在 `panel/`，内核同步在 `node-agent/`） |

## 配置

- LSP：在 Claude Code 中用 `/plugin` 安装 Go 与 TypeScript 语言服务器插件（gopls、vtsls 需先在 PATH 中）。
- MCP：设置 `GITHUB_MCP_PAT`。PostgreSQL 与 Valkey 的 MCP 自选维护中的实现，只连本地开发库并使用只读角色：
  ```sql
  CREATE ROLE claude_ro LOGIN PASSWORD 'dev-only';
  GRANT CONNECT ON DATABASE panel TO claude_ro;
  GRANT USAGE ON SCHEMA public TO claude_ro;
  GRANT SELECT ON ALL TABLES IN SCHEMA public TO claude_ro;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO claude_ro;
  ```
- Agent Teams 已在 `.claude/settings.json` 开启；子仓库内部关闭。
- `go.work.example`：panel-spec 与 panel/server 已有 go.mod（M0-03、M0-05），跨模块联调时复制为 `go.work`。

## 已验证

- `bootstrap.sh --org <组织>` 完整运行通过：7 个仓库各自有初始提交，workspace 工作区干净；node-agent 为 Xboard-Node 历史加本项目提交；两个内核 fork 位于 Xboard-Node go.mod 锁定的提交。
- 迁移在 PostgreSQL 上执行通过；proto 通过 buf lint；客户端 OpenAPI 通过 Redocly lint。
- Hooks 在嵌套仓库中生效：修改已提交的迁移被拒绝。
- 规格中的 `spec/NN` 引用全部有效，规则编号无重复。

## 未包含

- 业务代码（由 M1 起的任务生成）；PostgreSQL / Valkey 的 MCP 配置。
