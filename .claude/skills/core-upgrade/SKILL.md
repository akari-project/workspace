---
name: core-upgrade
description: 更新组织内的 sing-box 或 Xray-core fork（跟随 Xboard-Node 作者的 fork，或自行 rebase 官方上游），并让 node-agent 升级到新版本时使用。
---
# 同步上游内核

0. 首选：Xboard-Node 作者的内核 fork 已有新版本时，直接快进到其提交，跳到第 3 步。
1. 否则自行 rebase：在 `sing-box/` 或 `xray-core/` 中 `git fetch official --tags`，基于目标官方 tag 新建分支，逐个 cherry-pick `PATCHES.md` 中列出的补丁提交。
2. 冲突处理：只能调整补丁以适配上游，不得扩大补丁范围。无法解决时停止并报告冲突位置。
3. 在 fork 中运行上游自带测试，确认没有新增失败。
4. 打 tag：`<上游版本>-panel.<序号>`，例如 `v1.14.0-panel.1`。
5. 在同一提交中把 fork 的 panel-ci workflow 中 `UPSTREAM_BASE` 更新为新的上游基点（spec/02 CONV-25）。
6. 在 `node-agent/go.mod` 更新 `replace` 指向新 tag，运行 `make test && make conformance`。
7. 一致性测试覆盖全部协议 × 两个内核，失败项逐个分析是上游行为变化还是补丁问题，把上游行为变化记录到 `node-agent/internal/kernel/CLAUDE.md` 的“已知差异”。
8. 规模较大时，使用 `workflows/core-sync.md` 中的 Dynamic Workflow 并行执行第 6–7 步。
