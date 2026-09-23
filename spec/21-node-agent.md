# 21 节点 Agent

适用范围：`node-agent`（fork 自 cedar2025/Xboard-Node）、`sing-box` 与 `xray-core` 内核 fork。协议见 spec/20，计量见 spec/22。

## 21.1 保留、替换、新增

| 部分 | 处理 |
|---|---|
| 内核集成、入站构建、用户热更新、按用户计量、限速、活跃来源地址追踪 | 保留，数据来源改为本项目消息 |
| 证书（certmagic、DNS-01）、自定义路由与出站 | 保留，配置由 `RoutesApply` 下发 |
| 部署模式：节点、独立 | 保留；独立模式继续读本地文件 |
| 部署模式：机器（一个进程承载多个节点） | M5-03；1.0 之前的做法是每个节点各建一条连接，不改协议 |
| 安装脚本、Docker 镜像、`xbctl` | 改造：参数改为 `--server`、`--enroll-token`；命令行重命名为 `agentctl` |
| 与 Xboard 面板的通信、全局 API Key 鉴权、本地 `kernel.type` | 替换为 spec/20 的协议、接入令牌与控制面下发的内核 |
| 多面板多实例 | 代码保留，第一版只测试单一控制面 |
| WAL 与 `report_seq`、配额租约、离线租约、能力上报、按凭据计量 | 新增 |

- **AGT-01** 新代码放在新包中；对原有包只做接线级修改，并在 `UPSTREAM.md` 登记（文件、原因、冲突风险）。
- **AGT-02** Xboard-Node 原有文件保留 MPL-2.0 声明，并在 `REUSE.toml` 中登记（CONV-25）；新文件为 GPL-3.0-or-later；二进制整体按 GPL-3.0-or-later 分发；来源列入 `NOTICE`。
- **AGT-03** 每月挑选上游的内核、协议、证书修复合入；不再跟随上游通信层的改动。
- **AGT-04** 内核 fork 复制到本组织，并锁定到 Xboard-Node 当前 `replace` 所指的提交；`replace` 改为指向本组织的副本。优先合入 Xboard-Node 作者的 fork 更新，落后过久时自行 rebase。
- **AGT-05** 本地状态：
  - 只持久化以下内容，全部放在同一目录下：控制面地址、节点密钥、最后快照、WAL、租约状态、`report_seq` 计数器、信封去重记录。运行配置全部来自控制面。
  - 状态文件权限为 0600，目录为 0700。
  - 快照需要保留原始字节以便校验（spec/20 NODE-15），因此快照文件整体用由 PSK 派生的密钥（`HKDF-SHA256(PSK, info = "akari-agent-state-v1")`）做 AEAD 加密；其中的凭据值、入站私钥与 DNS 服务商凭据只在内存中以明文存在。
  - 控制面不可达时，按最后一次快照继续服务，本地租约与凭据到期时间继续生效，新连接按 spec/22 ACC-19 处理。
- **AGT-06** 不开放 HTTP 管理端口；指标只监听 127.0.0.1。

## 21.2 内核选择与协议矩阵

- **AGT-07** 内核由控制面按节点选择（默认 `singbox`），随 `SyncFull.kernel` 与 `InboundApply.kernel` 下发。
  - 与当前运行的内核不同时，Agent 先切换内核，再应用入站。
  - `InboundApply` 是该节点全部入站的全量替换。
  - 内核切换或入站应用失败时，Agent 回退到原内核与原入站，在 `ReportStatus` 中报告错误，并且不前进已应用的 `config_version`（spec/20 NODE-23）。
  - 本地 `kernel.type` 只在独立模式下生效。
- **AGT-08** 握手时，`Capabilities.kernels` 上报二进制内置的每个内核的版本、稳定协议、实验协议与支持的传输。
- **AGT-09** 控制面保存入站时做三层校验，不支持时返回 `kernel_protocol_unsupported`：
  - 数据库 `kernel_protocols` 与 `kernel_transports` 基线，由触发器强制；
  - 目标内核必须出现在该节点最近上报的 `Capabilities.kernels` 中；
  - 协议与传输必须在该节点上报的能力内。

  从未上报过能力、或上报的能力中没有传输信息（旧版本 Agent）的节点，只做基线校验。首次握手后发现不符的入站，标记为不可用并告警。Agent 降级导致能力缩小时，同样处理受影响的入站。
- **AGT-10** 实验协议只有在节点 `allow_experimental=true` 时才能启用。
- **AGT-11** 在 Xray 内核节点上配置 Reality 入站时，后台显示警告：自研客户端（mihomo）不兼容 Xray-core v26.7.11 及以上的 Reality 服务端，建议使用 sing-box 内核。
- **AGT-13** 入站 `settings_json` 的结构按“协议 + 传输”分别定义为 JSON Schema。管理接口中入站的 `settings` 不含私钥，私钥放在只写的 `secrets` 中（CONV-19）；控制面按 schema 校验两者合并后的结果。Schema 放在 `panel-spec/schemas/inbound/` 中，由控制面在保存时校验，并随 proto 一起版本化（ARC-01）。

| 协议 | sing-box | Xray-core |
|---|---|---|
| VLESS（Vision、Reality） | 稳定 | 稳定 |
| VMess | 稳定 | 稳定 |
| Trojan | 稳定 | 稳定 |
| Shadowsocks | 稳定 | 稳定 |
| Hysteria2 | 稳定 | 实验 |
| TUIC | 稳定 | 不支持 |
| AnyTLS | 稳定 | 不支持 |

| 传输 | sing-box | Xray-core |
|---|---|---|
| TCP（含 TLS、Reality） | 稳定 | 稳定 |
| WebSocket | 稳定 | 稳定 |
| gRPC | 稳定 | 稳定 |
| HTTPUpgrade | 稳定 | 稳定 |
| XHTTP | 不支持 | 稳定 |
| mKCP | 不支持 | 稳定 |
| QUIC（Hysteria2、TUIC 自带） | 稳定 | 实验（仅 Hysteria2） |

- **AGT-14** 入站 `settings` 必须包含 `transport`，值与 proto 的 `Inbound.transport` 一致；数据库校验以 `settings->>'transport'` 为准。Reality 只用于 VLESS（TCP、gRPC、XHTTP）与 AnyTLS（TCP）。具体的“协议 + 传输”组合见 `panel-spec/schemas/inbound/README.md`；组合范围与 mKCP 等字段在 M0-04 审计时确认，有变化时同步修改 schema 与本节。

基线随内核升级，通过新迁移更新；传输基线在 M0-04 审计后确认。XHTTP 与 mKCP 只有 Xray 提供，是选择 Xray 内核的主要理由。

## 21.3 内核接口

M0-04 审计后，把 Xboard-Node 现有的内核抽象对齐到以下能力（名称以 `FORK_PLAN.md` 为准）：

```go
type Kernel interface {
  Start(ctx context.Context, cfg InboundSet) error
  ApplyInbounds(cfg InboundSet) error          // 只中断被修改或删除的入站上的连接
  UpsertCreds(tag string, c []Credential) error // 不影响其他凭据的连接
  RemoveCreds(tag string, ids []string) error   // 关闭这些凭据的全部连接
  Sessions(credID string) []Session
  Capabilities() KernelSupport
  Close() error
}
```

- **AGT-12** 以下三项内核能力必须在两个内核上都成立，缺口在内核 fork 中补：
  - 增删凭据不影响其他连接；
  - 移除凭据后 1 秒内关闭其全部连接（TCP、UDP、QUIC 类、多路复用子连接）；
  - 按凭据计量误差为 0。计量口径为客户端与入站之间解密后的代理载荷字节，不含 TLS、QUIC 与代理协议头：上行为客户端 → 节点，下行为节点 → 客户端，多路复用子连接合并计入所属凭据。

  验收方法：用已知大小的载荷逐个协议、逐个传输测试，计数必须与载荷字节数完全相等。

## 21.4 生命周期

1. 启动：读取本地状态（AGT-05）；有快照时先按快照启动。
2. 连接：握手、上报能力与版本、接收同步、按 WAL 重传未确认的报告。
3. 运行：常规每 30 秒上报一次，账号剩余租约低于 20% 时缩短到 5 秒；执行租约；证书自动续期。
4. 退出（SIGTERM）：停止接受新连接，刷写 WAL，最多等待 30 秒后关闭。

## 21.5 安装

```bash
curl -fsSL https://get.运营者域名/agent.sh | sudo bash -s -- \
  --server https://gateway.运营者域名 --enroll-token <接入令牌>

docker run -d --restart=always --network=host \
  -e SERVER=https://gateway.运营者域名 -e ENROLL_TOKEN=<接入令牌> \
  -v /var/lib/node-agent:/var/lib/node-agent ghcr.io/<组织>/node-agent:<版本>
```

`agentctl` 子命令：`enroll`、`status`、`logs`、`doctor`（检查时钟、端口、证书、与控制面的连通性、本地状态文件权限）。
