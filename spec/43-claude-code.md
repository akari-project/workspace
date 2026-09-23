# 43 Claude Code 工作方式

适用范围：`workspace` 与各仓库的 `.claude/`、CLAUDE.md。

## 43.1 目录与加载

```
workspace/                 跨仓任务在这里启动 claude
├── CLAUDE.md              全局规则、完成的定义（导入 spec/02）
├── spec/                  规格（本目录）
├── adr/                   决策记录
├── backlog/               任务：M0–M5
├── workflows/             Dynamic Workflow 提示词
├── .claude/
│   ├── settings.json      权限、Hooks、开启 Agent Teams
│   ├── agents/            队员与审查者
│   └── skills/            跨仓 Skills
├── .mcp.json              GitHub、Playwright
├── panel-spec/            CLAUDE.md
├── panel/                 CLAUDE.md、.claude/；server/internal/* 各有 CLAUDE.md
├── node-agent/            CLAUDE.md、.claude/、FORK_PLAN.md、UPSTREAM.md
├── sing-box/  xray-core/  内核 fork
└── client/                CLAUDE.md（预留）
```

- 各代码仓库克隆在 `workspace/` 之下，因此从 `workspace/` 启动的会话可以访问全部仓库。
- 启动目录及其上级目录的 CLAUDE.md 在启动时加载；子目录的 CLAUDE.md 在读取该目录文件时加载；`--add-dir` 加入的目录默认不加载其 CLAUDE.md。
- 从 `workspace/` 启动时：只有 `workspace/.claude/settings.json` 生效（Hooks、权限、Agent Teams）；子仓库的 Skills 在接触其文件后按需发现。
- 子仓库是独立 git 仓库：git 操作用 `git -C <仓库>`。worktree 属于某个具体仓库，因此需要并行 worktree 的工作流在对应仓库目录内启动。

| 任务类型 | 启动目录 |
|---|---|
| 跨仓功能、规格评审、发版审计、Agent Teams | `workspace/` |
| 单仓任务 | 该仓库目录（例如 `workspace/panel/`），其 CLAUDE.md、settings、Skills 直接生效，上级 `workspace/CLAUDE.md` 也会加载 |
| 需要并行 worktree 的工作流 | 对应仓库目录（计费对抗在 `panel/`，内核同步在 `node-agent/`） |
- CLAUDE.md 只写该目录的**不变量与命令**，并引用规则编号；细节留在规格中，流程写成 Skills。

## 43.2 多代理模式

| 模式 | 用于 |
|---|---|
| 单会话 + 子代理 | 大多数任务；审查者：protocol-reviewer、concurrency-reviewer、security-reviewer、billing-verifier；补测试：test-writer |
| Agent Teams | 跨仓或前后端同时推进的功能；队员：spec-owner、panel-backend、frontend、agent-dev、e2e-tester，每人只改自己负责的仓库或目录 |
| Dynamic Workflow | 规格评审、计费对抗验证、内核同步矩阵测试、发版审计（提示词在 `workflows/`） |

- Agent Teams 只在 `workspace/.claude/settings.json` 中开启，各仓库内部关闭。
- 单个 bug 或小改动不组队。
- Workflow 先小范围试跑，确认用量后再扩大；执行类代理可用较快模型，编排与最终复核用 Opus。

## 43.3 Hooks 与权限

- 编辑前拦截：生成代码（`gen/`、`*.pb.go`、`*_gen.go`、`*.gen.ts`、sqlc 输出）、已提交的迁移、`.env*` 与密钥目录。
- 编辑后格式化：Go（goimports）、proto（buf format + lint）、前端（prettier）。
- 允许免确认：`go test`、`go build`、`make`、`buf`、`pnpm`、Redocly、只读 git 命令、`docker compose`。

## 43.4 MCP 与 LSP

- MCP：GitHub（细粒度令牌，只授权本组织仓库）、Playwright；PostgreSQL 与 Valkey 自选维护中的实现，只连本地开发环境，使用只读角色。任何 MCP 都不连接生产环境。
- LSP：gopls、vtsls（或 typescript-language-server）、buf、yaml-language-server；语言服务器需安装到 PATH，再通过插件接入。

## 43.5 与 Claude 协作的约定

- 每个会话从一个 backlog 任务开始：`执行 backlog/M1.md 的 M1-06，先给出计划`。
- 计划阶段列出将要满足的规则编号与验收标准；实施完成后逐条给出验证方式。
- 发现规格缺失或冲突时停止，提出修改建议，不自行决定。
- 上下文变长或切换任务时开新会话。

## 43.6 代理与 Skills 清单

| 名称 | 类型 | 位置 | 用途 |
|---|---|---|---|
| `agent-dev` | 代理 | workspace | 负责 node-agent（fork 自 Xboard-Node）以及 sing-box、xray-core 两个内核 fork：替换通信层、接入、控制面选内核、计量与 WAL、配额租约、安装与 agentctl。 |
| `billing-verifier` | 代理 | workspace | 对折算、价格锁定、权益状态机做对抗式验证，尝试构造让用户多付、少付或获得不应有权益的反例。 |
| `concurrency-reviewer` | 代理 | workspace | 审查 gateway、worker、node-agent 中的并发代码：锁、协程生命周期、通道关闭、竞态与背压。 |
| `e2e-tester` | 代理 | workspace | 编写与运行跨仓端到端测试（testcontainers + 模拟 Agent + 真实 Agent），在跨仓功能中负责验收。 |
| `frontend` | 代理 | workspace | 负责 panel/web：用户中心（portal）、管理后台（admin）、共享组件（ui）与生成的 SDK（sdk）。 |
| `panel-backend` | 代理 | workspace | 负责 panel/server（Go 控制面后端）：API、gateway、worker、计费、权限协调、迁移。 |
| `protocol-reviewer` | 代理 | workspace | 审查 proto 与 OpenAPI 变更的向后兼容性、能力位与命名约定。修改 panel-spec 后使用。 |
| `security-reviewer` | 代理 | workspace | 审查鉴权、令牌、密钥、日志脱敏、输入校验与依赖许可证。合并涉及账号、支付、节点接入的改动前使用。 |
| `spec-owner` | 代理 | workspace | 负责 panel-spec 仓库（proto 与 OpenAPI）以及 workspace/spec 规格文档。跨仓功能中第一个开工，定义契约并回答其他队员关于契约的问题。 |
| `test-writer` | 代理 | workspace | 为指定改动补充单元测试、表驱动用例与性质测试。 |
| `add-opcode` | Skill | workspace | 在节点协议中新增一种消息（控制面下发或节点上报）时使用，给出跨三个仓库的检查清单。适合以 Agent Teams 执行。 |
| `core-upgrade` | Skill | workspace | 更新组织内的 sing-box 或 Xray-core fork（跟随 Xboard-Node 作者的 fork，或自行 rebase 官方上游），并让 node-agent 升级到新版本时使用。 |
| `e2e-scenario` | Skill | workspace | 编写跨仓端到端测试时使用：启动 PostgreSQL、Valkey、控制面与模拟或真实 Agent，按业务流程断言。 |
| `spec-change` | Skill | workspace | 修改节点协议（proto）或客户端接口（OpenAPI）时使用。覆盖从改规范、兼容检查、能力位、打 tag 到各仓升级依赖的完整流程。 |
| `accounting-change` | Skill | panel | 修改流量计量、上报、Valkey 入账脚本、落库或分区维护时使用。 |
| `billing-change` | Skill | panel | 修改套餐、价格、报价、订单、折算、权益状态机或到期处理时使用。 |
| `client-api-endpoint` | Skill | panel | 新增或修改 /v1 客户端接口时使用。 |
| `db-migration` | Skill | panel | 新增或修改数据库表、列、索引、约束、触发器时使用。 |
| `export-adapter` | Skill | panel | 为第三方客户端新增一种配置导出格式，或修改已有格式时使用。 |
| `payment-provider` | Skill | panel | 修改内置支付宝当面付，或新增一个内置支付渠道时使用。 |
| `release` | Skill | panel | 发布 panel 新版本时使用。 |
| `kernel-conformance` | Skill | node-agent | 修改 Kernel 接口、任一内核实现或 fork 补丁后使用，确保两个内核行为一致。 |
| `upstream-sync` | Skill | node-agent | 检查并挑选合入上游 Xboard-Node 的修复时使用（每月一次，或上游发布安全修复时）。 |
