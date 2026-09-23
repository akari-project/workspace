# 42 工程规范、测试与发布

适用范围：全部仓库。

## 42.1 兼容性

- **ENG-01** proto：字段只增不改；删除的字段编号写入 `reserved`；新行为配能力位。`buf breaking` 必须通过。
- **ENG-02** OpenAPI：`/v1` 冻结后只增可选字段；新增错误码先加入 spec/02。Redocly lint 必须通过。
- **ENG-03** 控制面 × Agent × 协议的兼容矩阵维护在 `panel` 与 `node-agent` 的 README 中；控制面至少兼容前两个 Agent 小版本。
- **ENG-04** 语义化版本；1.0 之前小版本可以有破坏性变更，但必须在 CHANGELOG 中说明迁移方法。

## 42.2 持续集成

| 仓库 | 检查 |
|---|---|
| 全部 | SPDX 头、依赖许可证扫描、`govulncheck` 或 `pnpm audit` |
| panel-spec | `buf lint`、`buf breaking`、两份 OpenAPI 的 Redocly lint、生成代码无差异 |
| panel | `go test -race`、`staticcheck`、性质测试、端到端测试（testcontainers）、前端 lint / typecheck / test / build、嵌入产物一致性 |
| node-agent | `go test -race`、协议一致性套件、内核一致性测试 |

## 42.3 测试层次

| 层次 | 工具 | 说明 |
|---|---|---|
| 单元 | Go testing、Vitest | 所有包 |
| 性质 | rapid | 折算、状态机、权限协调（spec/11.7） |
| 集成 | testcontainers（PostgreSQL 18、Valkey） | 迁移、Lua 脚本、落库 |
| 端到端 | `panel/server/e2e`、Playwright | 业务流程；用例名引用任务编号，如 `TestM1_06_...` |
| 协议一致性 | `panel/server/e2e/conformance` | 同一套件对模拟 Agent 与真实 Agent 运行 |
| 混沌 | `make chaos` | 计量链路 |

- **ENG-05** 端到端测试不使用 `time.Sleep` 等待，统一使用带超时的等待函数与可注入时钟。
- **ENG-06** 每条 backlog 验收标准至少对应一个自动化测试，手动验收项在 PR 中记录过程。

## 42.4 指标目标

以下为设计目标，结果与脚本放在 `panel/bench`，随版本发布。

| 指标 | 目标 | 条件 |
|---|---|---|
| 导出配置吞吐 | ≥ 10,000 RPS | 单实例 4 vCPU / 8 GB，10 万账号、50 节点，304 占 90% |
| `/v1/me/configuration` | P99 < 50 ms | 缓存命中 |
| 处置时延 | P99 < 1 s | 判决到所有在线节点关闭会话；3 个网关实例 |
| 最大超额 | ≤ 256 MiB | 5 节点并发满速，默认租约参数 |
| 计费准确性 | 误差 0 字节 | 混沌测试 |
| 重连收敛 | P99 < 60 s | 1,000 节点同时断开 |
| 权限收敛 | P99 < 5 s | 影响 1 万账号的线路组调整 |
| Agent 内存 | 空载 < 40 MB | 另报告每 1,000 连接的增量；两个内核分别测量 |

## 42.5 发布

- GoReleaser 多平台构建；二进制与镜像用 cosign 签名，附 SBOM 与构建来源证明。
- 发版前运行 `workflows/release-audit.md`；CHANGELOG 分新增、变更、修复、安全；列出本版迁移及能否在线执行。

## 42.6 治理

- `.github` 仓库提供 SECURITY.md（私密报告渠道、响应时限、支持版本）、CODE_OF_CONDUCT.md、PR 模板（DCO、验收标准清单）。
- 重大决策写 ADR（`../adr/`）。README 说明项目用途与部署者需遵守所在地法律法规。
