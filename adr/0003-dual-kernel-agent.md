# ADR 0003：Agent 单二进制内嵌双内核，由控制面选择内核

- 状态：已接受（2026-09 修订：内核改由控制面选择；Agent 实现方式见 ADR 0012）
- 日期：2026-09

## 背景
Xboard-Node 在单一 go.mod 中同时引入 sing-box 与 Xray-core，通过 replace 指向维护的 fork，运行时由本地配置 `kernel.type` 选择内核。两个内核支持的协议不同：sing-box 覆盖本项目全部 7 种协议；Xray-core 不支持 TUIC 与 AnyTLS，其 Hysteria2 实现较新；XHTTP、mKCP 为 Xray 独有。

## 决定
- 单一二进制内嵌两个内核，保留 build tag 以构建单内核精简版。
- 内核由控制面按节点选择，默认 sing-box，随全量同步下发；本地 `kernel.type` 只在独立模式下生效。
- 数据库维护 `kernel_protocols` 基线矩阵，触发器保证入站协议被所选内核支持；Xray 的 Hysteria2 标为实验，需节点显式允许。
- Agent 握手上报内置的每个内核及其协议，控制面在应用层再次校验。

## 影响
- 运维在后台即可切换内核或做灰度对比，无需登录服务器。
- 基线矩阵随内核升级通过新迁移更新。
