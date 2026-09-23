# ADR 0002：许可证

- 状态：已接受
- 日期：2026-09

## 背景
sing-box 为 GPL-3.0-or-later，链接它的程序须 GPL 兼容；希望托管服务的修改也回馈社区；协议需要被任何人实现。

## 决定
控制面 AGPL-3.0-or-later；Agent 与客户端 GPL-3.0-or-later；panel-spec 与生成的 SDK Apache-2.0。贡献采用 DCO，不使用 CLA。

## 影响
不能单方面更换许可证或做商业双许可；所有支付渠道随控制面开源（ADR 0015）。
