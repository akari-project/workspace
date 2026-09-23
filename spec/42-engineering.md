# 42 工程规范、测试与发布

适用范围：全部仓库。

## 42.1 兼容性

- **ENG-01** proto：字段只增不改；删除的字段编号写入 `reserved`；新行为配能力位。`buf breaking` 必须通过。
- **ENG-02** OpenAPI：
  - `/v1` 冻结后只增可选字段；新增错误码先加入 spec/02。
  - Redocly lint 必须通过。
  - CI 用 `oasdiff breaking --fail-on ERR` 与上一个 tag 比较。1.0 之前允许破坏性变更，但必须在 CHANGELOG 中列出（ENG-04）。
- **ENG-03** 控制面 × Agent × 协议的兼容矩阵，维护在 `panel` 与 `node-agent` 的 README 中。
  - 控制面至少兼容前两个 Agent 小版本。
  - Agent 比控制面新时，按控制面在 `HelloAck` 中声明的协议版本与能力位运行（spec/40 DEP-09）。
- **ENG-04** 使用语义化版本。1.0 之前小版本可以有破坏性变更，但必须在 CHANGELOG 中说明迁移方法。

## 42.2 持续集成

每个仓库都提供 `make ci`，内容与下表中该仓库的检查一一对应，本地与 CI 执行同一目标。`make test` 只含单元测试与需要容器的集成测试（`-race`），是 `make ci` 的一部分。

| 仓库 | 检查 |
|---|---|
| 全部 | SPDX 头（REUSE lint，CONV-25）；依赖许可证扫描（按下方允许清单）；`govulncheck` 或 `pnpm audit` |
| panel-spec | `buf lint`、`buf breaking`；两份 OpenAPI 的 Redocly lint 与 oasdiff；禁用词检查（spec/30 API-01）；`x-permission` 取值检查（spec/10 AUTH-17）；每个操作都有响应示例；生成代码无差异 |
| panel | `make test`、`staticcheck`、性质测试、端到端测试（testcontainers）；前端 lint / typecheck / test / build；嵌入产物一致性（spec/40 DEP-01） |
| node-agent | `make test`、协议一致性套件、内核一致性测试（只跑协议矩阵中“稳定”与“实验”的组合） |

依赖许可证允许清单：

| 仓库许可证 | 允许的依赖许可证 |
|---|---|
| Apache-2.0（panel-spec、workspace） | MIT、BSD-2-Clause、BSD-3-Clause、Apache-2.0、ISC |
| GPL-3.0 与 AGPL-3.0（panel、node-agent、client） | 上一行全部，加 MPL-2.0、LGPL-2.1+、LGPL-3.0、GPL-3.0；panel 另外允许 AGPL-3.0 |

禁止 SSPL、BUSL、Commons Clause，以及没有许可证的依赖。清单以外的依赖必须在仓库根目录的 `LICENSE-EXCEPTIONS` 中登记理由。

- **ENG-07** 对抗验证（`workflows/billing-adversarial.md`）确认的反例测试，放在 `//go:build adversarial` 标签下，不进入默认的 `make test`。CI 另设非阻塞任务 `make test-adversarial`，并在 PR 中显示结果；问题修复后去掉构建标签，转为常规测试。

## 42.3 测试层次

| 层次 | 工具 | 说明 |
|---|---|---|
| 单元 | Go testing、Vitest | 所有包 |
| 性质 | rapid | 折算、状态机、权限协调（spec/11 11.9） |
| 集成 | testcontainers（PostgreSQL 18、Valkey） | 迁移、Lua 脚本、落库 |
| 端到端 | `panel/server/e2e`、Playwright | 业务流程；用例名引用任务编号，如 `TestM1_06_...` |
| 协议一致性 | `panel/server/e2e/conformance` | 同一套件对模拟 Agent 与真实 Agent 运行 |
| 混沌 | `make chaos` | 计量链路（spec/22 22.6） |

- **ENG-05** 端到端测试不使用 `time.Sleep` 等待，统一使用带超时的等待函数与可注入时钟。
- **ENG-06** 每条 backlog 验收标准至少对应一个自动化测试，手动验收项在 PR 中记录过程。

## 42.4 指标目标

以下为设计目标，结果与脚本放在 `panel/bench`，随版本发布。backlog 中已作为验收标准的指标（超额、处置时延、重连收敛）必须达标；其余指标比上一版本退化超过 20% 或未达目标的，必须在 CHANGELOG 中说明。

| 指标 | 目标 | 条件与测量口径 |
|---|---|---|
| 导出配置吞吐 | ≥ 10,000 RPS | 单实例 4 vCPU / 8 GB，10 万账号、50 节点，304 占 90% |
| `/v1/me/configuration` | P99 < 50 ms | 缓存命中 |
| 处置时延 | P99 < 1 s | 从权益状态变更写入 PostgreSQL，到所有在线节点关闭相关连接；3 个网关实例 |
| 最大超额 | ≤ 256 MiB | 5 节点并发满速，默认租约参数（spec/22 ACC-11） |
| 计费准确性 | 误差 0 字节（原始字节） | 混沌测试，按 spec/22 ACC-07 区分故障类型 |
| 重连收敛 | P99 < 60 s | 1,000 节点同时断开；收敛指全部节点 `online`，且已应用的 `config_version` 等于控制面当前值 |
| 权限收敛 | P99 < 5 s | 影响 1 万账号的线路组调整 |
| Agent 内存 | 空载 RSS < 40 MB | 另报告每 1,000 连接的 RSS 增量；两个内核分别测量 |

## 42.5 发布

- GoReleaser 多平台构建；二进制与镜像用 cosign 签名，附 SBOM 与构建来源证明。
- 发版前运行 `workflows/release-audit.md`。CHANGELOG 分新增、变更、修复、安全四部分，并列出本版的迁移及能否在线执行（spec/40 DEP-12）。

## 42.6 治理

- `.github` 仓库提供 SECURITY.md（私密报告渠道、响应时限、支持版本）、CODE_OF_CONDUCT.md、PR 模板（DCO、验收标准清单）。
- 重大决策写 ADR（`../adr/`）。README 说明项目用途，以及部署者需遵守所在地的法律法规。
