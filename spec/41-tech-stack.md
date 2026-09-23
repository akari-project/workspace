# 41 技术选型

适用范围：全部仓库。选型的决策记录见 ADR 0009、0010、0014、0016。状态为“提议”的选型可以在 M0 结束前修改。

## 41.1 控制面后端（`panel/server`）

| 用途 | 选型 | 理由 |
|---|---|---|
| 语言 | Go（支持最新两个稳定版） | 与 Agent 同语言，团队只需掌握一种后端语言 |
| HTTP 路由 | 标准库 `net/http`（1.22+ 路由模式） | 无第三方依赖；OpenAPI 生成代码对接标准库 |
| OpenAPI 代码生成 | oapi-codegen（strict server 模式） | 从 `panel-spec` 生成类型与接口，手写部分只实现业务 |
| 数据库 | PostgreSQL 18 | `uuidv7()`、分区表 |
| 数据库驱动 | pgx v5 | PostgreSQL 专用，性能与功能最好 |
| SQL | sqlc，输出目录 `server/internal/db/sqlc/` | SQL 写在 `.sql` 文件中，生成类型安全的 Go 代码，便于 Claude 审查 |
| 迁移 | goose | SQL 文件迁移，支持嵌入 Go；由 `panel migrate` 执行（spec/40 DEP-12） |
| Valkey | Valkey 8 及以上（开发环境使用 9），客户端 valkey-go | Valkey 官方客户端，支持自动流水线与客户端缓存；Lua 脚本依赖 8 以上的行为 |
| WebSocket | coder/websocket | 维护活跃，基于 context，API 简洁 |
| Protobuf | buf + protoc-gen-go | 与 `panel-spec` 一致 |
| 加密 | 标准库与 `golang.org/x/crypto`（chacha20poly1305、curve25519、hkdf、argon2） | 只用官方与准官方实现 |
| 令牌 | PASETO v4.public（go-paseto） | 见 spec/10 AUTH-06 |
| 日志 | `log/slog` | 标准库 |
| 指标 | Prometheus client_golang | 事实标准 |
| 配置 | 环境变量 + 单一 YAML 文件，启动时校验 | 简单，可以在容器中覆盖 |
| 测试 | 标准库 testing、testcontainers-go、rapid（性质测试） | 性质测试用于折算与状态机 |

## 41.2 前端（`panel/web`）

| 用途 | 选型 | 理由 |
|---|---|---|
| 运行时 | Node.js 22 LTS | 与 CI 和 README 一致 |
| 框架 | React + TypeScript + Vite | 生态最大，Claude 生成质量稳定 |
| 包管理 | pnpm workspace（`portal`、`admin`、`ui`、`sdk` 四个包） | 两个应用共享组件与 SDK |
| 路由与数据 | TanStack Router + TanStack Query | 类型安全的路由；请求缓存与重试 |
| API 客户端 | openapi-typescript + openapi-fetch | 从 OpenAPI 直接生成类型，运行时极薄 |
| 组件 | Radix UI 基础组件 + Tailwind CSS，组件源码放在 `ui` 包内 | 可定制主题，无运行时样式库 |
| 表单 | React Hook Form + Zod | Zod 模式可以从 OpenAPI 生成 |
| 国际化 | i18next | 语言包按命名空间拆分 |
| 图表 | Recharts | 用量与收入图表足够 |
| 测试 | Vitest + Testing Library；端到端用 Playwright | Playwright 同时作为 MCP 服务供 Claude 使用 |

如果团队更熟悉 Vue，可以在 M0 用 ADR 改为 Vue 3 + Vite + Pinia + TanStack Query（Vue 版），其余结构不变。

前端构建产物嵌入控制面二进制，见 spec/40。

## 41.3 节点 Agent（`node-agent`）

| 用途 | 选型 |
|---|---|
| 内核 | 组织内的 sing-box 与 Xray-core fork（见 spec/21） |
| 证书 | certmagic + libdns 各 DNS 服务商 |
| 系统信息 | gopsutil |
| WebSocket 与信封 | 与控制面相同（coder/websocket、`panel-spec` 生成代码） |
| 本地存储 | 单个目录下的文件，内容与权限见 spec/21 AGT-05；不引入嵌入式数据库 |
| 命令行 | `agentctl`，标准库 `flag` 子命令 |

## 41.4 基础设施

| 用途 | 选型 |
|---|---|
| 前置 Web 服务器 | 可选。控制面二进制已内置前端；需要自动 HTTPS 时，在前面放 Caddy（spec/40 DEP-13） |
| 本地与单机部署 | Docker Compose |
| 多实例部署 | Helm Chart（M5） |
| CI | GitHub Actions |
| 发布 | GoReleaser、cosign（固定密钥签名，spec/40 DEP-09）、Syft 生成 SBOM |
| 容器镜像仓库 | GHCR |
| PostgreSQL 备份 | pgBackRest |
| 许可证与 SPDX | REUSE（`REUSE.toml` 登记上游文件，spec/02 CONV-25） |
| OpenAPI 兼容检查 | oasdiff（spec/42 ENG-02） |

## 41.5 自研客户端（`client`，预留）

| 用途 | 选型 |
|---|---|
| 内核 | mihomo（GPL-3.0），各平台以库的形式嵌入（ADR 0014） |
| 配置 | 从 `/v1/me/configuration` 在本地生成 mihomo 配置 |
| 界面框架 | 1.0 之后立项时决定 |
