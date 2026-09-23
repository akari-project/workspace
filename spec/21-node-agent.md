# 21 节点 Agent

适用范围：`node-agent`（fork 自 cedar2025/Xboard-Node）、`sing-box` 与 `xray-core` 内核 fork。协议见 spec/20，计量见 spec/22。

## 21.1 保留、替换、新增

| 部分 | 处理 |
|---|---|
| 内核集成、入站构建、用户热更新、按用户计量、限速、活跃来源地址追踪 | 保留，数据来源改为本项目消息 |
| 证书（certmagic、DNS-01）、自定义路由与出站 | 保留，配置由 `RoutesApply` 下发 |
| 部署模式：节点、机器、独立 | 保留；独立模式继续读本地文件 |
| 安装脚本、Docker 镜像、`xbctl` | 改造：参数改为 `--server`、`--enroll-token`；命令行重命名为 `agentctl` |
| 与 Xboard 面板的通信、全局 API Key 鉴权、本地 `kernel.type` | 替换为 spec/20 的协议、接入令牌与控制面下发的内核 |
| 多面板多实例 | 代码保留，第一版只测试单一控制面 |
| WAL 与 `report_seq`、配额租约、能力上报、按凭据计量 | 新增 |

- **AGT-01** 新代码放在新包中；对原有包只做接线级修改，并在 `UPSTREAM.md` 登记（文件、原因、冲突风险）。
- **AGT-02** Xboard-Node 原有文件保留 MPL-2.0 声明；新文件为 GPL-3.0-or-later；二进制整体按 GPL-3.0-or-later 分发；来源列入 `NOTICE`。
- **AGT-03** 每月挑选上游的内核、协议、证书修复合入；不再跟随上游通信层的改动。
- **AGT-04** 内核 fork 复制到本组织并锁定到 Xboard-Node 当前 `replace` 所指提交；`replace` 指向本组织副本。优先合入 Xboard-Node 作者的 fork 更新，落后过久时自行 rebase。
- **AGT-05** 本地只保存控制面地址与节点密钥；运行配置全部来自控制面。控制面不可达时按最后一次快照继续服务，本地租约与凭据到期时间继续生效。
- **AGT-06** 不开放 HTTP 管理端口；指标只监听 127.0.0.1。

## 21.2 内核选择与协议矩阵

- **AGT-07** 内核由控制面按节点选择（默认 `singbox`），随 `SyncFull.kernel` 与 `InboundApply.kernel` 下发；与当前运行的不同时，Agent 先切换内核再应用入站。本地 `kernel.type` 只在独立模式下生效。
- **AGT-08** 握手时 `Capabilities.kernels` 上报二进制内置的每个内核、版本、稳定协议与实验协议。
- **AGT-09** 控制面保存入站时两层校验：数据库 `kernel_protocols` 基线（触发器强制）与该节点最近上报的能力（应用层）。不支持返回 `kernel_protocol_unsupported`。
- **AGT-10** 实验协议只有在节点 `allow_experimental=true` 时才能启用。
- **AGT-11** 在 Xray 内核节点上配置 Reality 入站时，后台显示警告：自研客户端（mihomo）不兼容 Xray-core v26.7.11 及以上的 Reality 服务端，建议使用 sing-box 内核。

| 协议 | sing-box | Xray-core |
|---|---|---|
| VLESS（Vision、Reality） | 稳定 | 稳定 |
| VMess | 稳定 | 稳定 |
| Trojan | 稳定 | 稳定 |
| Shadowsocks | 稳定 | 稳定 |
| Hysteria2 | 稳定 | 实验 |
| TUIC | 稳定 | 不支持 |
| AnyTLS | 稳定 | 不支持 |

基线随内核升级通过新迁移更新。XHTTP、mKCP 只有 Xray 提供，是选择 Xray 内核的主要理由。

## 21.3 内核接口

M0-04 审计后，把 Xboard-Node 现有的内核抽象对齐到以下能力（名称以 `FORK_PLAN.md` 为准）：

```go
type Kernel interface {
  Start(ctx context.Context, cfg InboundSet) error
  ApplyInbounds(cfg InboundSet) error          // 可能中断该入站连接
  UpsertCreds(tag string, c []Credential) error // 不影响其他凭据的连接
  RemoveCreds(tag string, ids []string) error   // 关闭这些凭据的全部会话
  Sessions(credID string) []Session
  Capabilities() KernelSupport
  Close() error
}
```

- **AGT-12** 三项内核能力必须在两个内核上都成立：增删凭据不影响其他连接；按凭据计量误差为 0；移除凭据后 1 秒内关闭其全部会话（TCP、UDP、QUIC 类、多路复用子连接）。缺口在内核 fork 中补。

## 21.4 生命周期

1. 启动：读取节点密钥、最后快照（含内核）、未确认 WAL；有快照先按快照启动。
2. 连接：握手、上报能力与版本、接收同步、重传 WAL。
3. 运行：常规 30 秒上报，账号剩余租约低于 20% 时缩短到 5 秒；执行租约；证书自动续期。
4. 退出（SIGTERM）：停止接受新连接，刷写 WAL，最多等待 30 秒后关闭。

## 21.5 安装

```bash
curl -fsSL https://get.运营者域名/agent.sh | sudo bash -s -- \
  --server https://gateway.运营者域名 --enroll-token <接入令牌>

docker run -d --restart=always --network=host \
  -e SERVER=https://gateway.运营者域名 -e ENROLL_TOKEN=<接入令牌> \
  -v /var/lib/node-agent:/var/lib/node-agent ghcr.io/<组织>/node-agent:<版本>
```

`agentctl` 子命令：`enroll`、`status`、`logs`、`doctor`（检查时钟、端口、证书、与控制面的连通性）。
