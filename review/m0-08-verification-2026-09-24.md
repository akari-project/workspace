<!-- SPDX-License-Identifier: Apache-2.0 -->

# M0-08 本地环境与 Claude Code 配置验证（2026-09-24）

范围：backlog/M0.md 的 M0-08；规则 spec/43 43.2、43.3、43.4。

## 验收 1：Hooks

自动化：`make test-hooks`（`scripts/hooks/test-hooks.sh`，已加入 `make ci` 与 workspace CI），19 个用例：

- guard-paths.sh 拒绝：`gen/` 下的 `.pb.go` 与 `.d.ts`、`*_gen.go`、`gen/` 之外的 `*.pb.go`、`*.gen.ts`（panel/web/sdk）、`server/internal/db/sqlc/`、已提交的迁移、`.env`、`.env.local`、`secrets/`；`path` 键同样识别。
- guard-paths.sh 允许：普通文件、未跟踪的新迁移、`ALLOW_MIGRATION_EDIT=1` 时的已提交迁移、没有文件路径的输入。
- post-edit.sh：未格式化的 Go 文件编辑后与 `gofmt` 输出一致；不存在的文件与非 Go 文件不报错。
- 反向验证：从 guard-paths.sh 的副本中删去 `*.pb.go` 模式后，`gen/` 之外的 `api.pb.go` 用例失败（18 通过，1 失败）。

手动验收（本会话，从 workspace 启动，`.claude/settings.json` 的 hooks 生效）：

| 操作 | 结果 |
|---|---|
| Write `panel-spec/gen/ts/client.d.ts`（panel-spec 的克隆） | 被拒绝：“是生成代码。请修改源……后运行 make gen。” |
| Edit `panel/server/migrations/00001_init.sql`（panel 的克隆，已提交） | 被拒绝：“已提交，迁移只能新增不能修改。” |
| Write 一个未格式化的 `x.go` | 写入后被格式化（环境中没有 goimports，退回 gofmt） |

panel 仓库的 `.claude/hooks/` 两个脚本与 `scripts/hooks/` 逐字节相同。

## 验收 2：Agent Teams 示例任务

在 workspace 中由 lead 组建两名队员，并行完成本任务的交付物，lead 事先约定接口（脚本路径、`make test-hooks` 目标名）并负责复核与提交：

| 队员 | 代理定义 | 负责 | 结果 |
|---|---|---|---|
| hook-tester | `test-writer` | hook 测试脚本、Makefile 目标、CI 步骤 | 完成测试脚本与反向验证；其代理定义只允许编辑测试文件，因此脚本写在临时目录，由 lead 放入仓库 |
| doc-writer | `spec-owner` | README“开发者工具与版本”一节 | 完成；另指出 README 中两处过时说明，已由 lead 修正 |

观察：
- 两名队员只改各自的文件，没有冲突。
- `test-writer` 的编辑范围限于测试文件，不适合承担 `scripts/`、Makefile、CI 的修改；这类任务应分配给拥有全部工具的队员，或由 lead 放入。

## 验收 3：README

README 新增“开发者工具与版本”一节。版本取自各仓库的实际文件：

- panel/server、panel-spec 的 `go.mod`；
- panel/web 的 `packageManager` 与 `engines`；
- panel-spec 的 CI（buf）；
- panel、panel-spec 的 Makefile（Redocly、oasdiff、sqlc 等）；
- `compose.dev.yaml`。

## 发现（未在本任务中修改）

1. guard-paths.sh 的模式以 `*/` 开头，相对路径（如 `gen/a.go`、`secrets/x`）可以绕过；从仓库内以相对路径编辑已提交迁移时，`git -C "$dir" ls-files "$f"` 会把路径重复拼接，结果被放行。编辑工具通常传绝对路径，风险低。
2. `*.env.*` 同时匹配 `config.env.example`、`foo.env.ts`；spec/43 43.3 写的是 `.env*`，模式可收窄为 `*/.env|*/.env.*`。
3. 输入 JSON 解析失败时 hook 放行（不是失败即拒绝）。
4. panel-spec 由 `make gen` 生成的 `schemas/inbound/*.json` 与 `testdata/node-v1-vectors.json` 不在 spec/43 43.3 的拦截清单中，编辑不会被拒绝；可由 panel-spec 的“生成代码无差异”检查兜底。若要拦截，需要先修改 43.3。
5. panel 的 `.claude/settings.json` 允许 `Bash(pnpm:*)` 与 `Bash(docker compose:*)`，比 43.3 宽（43.3 明确 `pnpm dlx`、`pnpm exec`、`docker compose down -v` 不免确认），应与 workspace 的列表对齐。

第 1–3 项修改 hook 时，须同时修改 panel 的 `.claude/hooks/`，使两份保持一致。
