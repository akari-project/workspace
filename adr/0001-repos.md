# ADR 0001：四个仓库的划分

- 状态：已接受
- 日期：2026-09

## 背景
控制面、节点 Agent、客户端的许可证、发版节奏、依赖树与贡献者群体都不同；协议需要一个中立的位置。

## 决定
拆为 `panel-spec`（Apache-2.0）、`panel`（AGPL-3.0-or-later）、`node-agent`（GPL-3.0-or-later）、`client`（GPL-3.0-or-later，1.0 后启动），另设组织级 `.github` 与本地 `workspace`。两个内核 fork 作为独立仓库。

## 影响
跨仓改动需要按 spec-change 流程分步合并；通过能力位解耦合并顺序。
