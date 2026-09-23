# workspace

开源 VPN 控制面板的本地工作区。跨仓库任务在这里启动 Claude Code。

## 项目一句话
可自托管的代理服务管理系统：控制面 `panel`（Go，内嵌用户中心与管理后台两个前端）负责账号、套餐、计费、支付宝收款与节点编排；节点 `node-agent`（fork 自 Xboard-Node，内嵌 sing-box / Xray）承载流量；协议与接口定义在 `panel-spec`。

## 先读什么
1. `spec/README.md`：规格索引、阅读规则、按角色的阅读顺序。
2. `spec/00-glossary.md`：中文术语与代码标识符对照。
3. 当前任务在 `backlog/` 中的条目：仓库、模式、依赖、规格、验收标准。

@spec/02-conventions.md

## 仓库
| 目录 | 内容 | 许可证 |
|---|---|---|
| panel-spec/ | 节点协议 proto、客户端与管理接口 OpenAPI | Apache-2.0 |
| panel/ | 控制面后端 server/ + 前端 web/（portal、admin、ui、sdk） | AGPL-3.0-or-later |
| node-agent/ | fork 自 Xboard-Node，通信层改为本项目协议 | GPL-3.0-or-later（原有文件保留 MPL-2.0） |
| sing-box/、xray-core/ | 内核 fork | 继承上游 |
| client/ | 自研客户端（1.0 之后），内嵌 mihomo | GPL-3.0-or-later |

这些仓库位于本目录之下（首次由 `scripts/bootstrap.sh` 建立，其他开发者用 `scripts/clone-all.sh` 克隆），因此从这里启动的会话可以直接读写全部仓库。

## 嵌套仓库须知
- 每个子目录是**独立的 git 仓库**，已被本仓库的 .gitignore 忽略。git 命令必须在对应仓库执行：`git -C panel status`、`git -C node-agent commit ...`。禁止在 workspace 根目录对子仓库文件执行 git 操作。
- Hooks 与权限只使用本目录的 `.claude/settings.json`（子仓库的 settings 在从这里启动时不生效，内容相同）。
- 子仓库的 Skills 在会话接触该目录的文件后才会被发现；若需要的 Skill 没有出现，直接读取其 `SKILL.md`（位置见 spec/43.6）。
- 需要并行 worktree 的任务（工作流、多名队员同改一个仓库）应在该仓库目录内启动，见 `workflows/README.md`。

## 已定的关键决策（不要重新讨论，除非任务要求）
- 控制面优先：M1 控制面与两个前端 → M2 节点编排（模拟 Agent）→ M3 Agent 改造（ADR 0013）。
- 节点内核由控制面选择，默认 sing-box；协议矩阵见 spec/21（ADR 0003）。
- 没有宽限期：到期即回到免费账号；续费只在有效期内；续费不重置流量；老用户续费按锁定价格（spec/11）。
- 支付只内置支付宝当面付，参数在后台配置（spec/12，ADR 0015）。
- 前端嵌入控制面二进制（spec/40，ADR 0016）。
- 对外接口命名中性，禁止 subscribe、server、node、traffic（spec/30 API-01）。

## 工作规则
- 规格是唯一依据；契约文件（proto、OpenAPI、迁移）是字段级事实来源。发现规格缺失或冲突时停止并提出修改，不自行决定。
- 计划阶段列出要满足的规则编号（如 `BIL-07`）与验收标准；完成后逐条说明验证方式。
- 协议或接口变更先改 `panel-spec`（`spec-change` Skill），一次提交只改一个仓库（ARC-01、ARC-02）。
- 多代理：默认单会话 + 子代理；跨仓或前后端同时推进用 Agent Teams；大范围并行或对抗验证用 `workflows/` 中的 Dynamic Workflow（spec/43）。单个 bug 不组队。

## 完成的定义
1. 相关仓库 `make ci` 通过（与 spec/42 42.2 该仓库的检查一一对应，含 `-race` 单元与集成测试、性质测试、端到端测试、静态检查、前端检查）；涉及 proto 时 `buf breaking` 通过，涉及 OpenAPI 时 Redocly lint 与 oasdiff 通过。
2. backlog 中该任务的验收标准逐条满足，每条对应自动化测试或记录的手动验收。
3. 涉及的规则编号全部满足。
4. 没有新增对外禁用词、没有日志输出令牌或凭据（CONV-24）、新文件带 SPDX 头（CONV-25）。
5. 更新 backlog 中该任务的状态。

## 常用命令
- `scripts/bootstrap.sh [--org <组织>]`：首次建立本地工作区
- `scripts/clone-all.sh <github-org>`：从 GitHub 克隆全部仓库
- `docker compose -f compose.dev.yaml up -d`：PostgreSQL 18、Valkey、Mailpit
- `cp go.work.example go.work`：本地跨模块联调
