创建并运行一个 workflow，对 `panel/server/internal/billing` 与 `internal/access` 做对抗式验证。在 `workspace/panel/` 中启动；所用的 billing-verifier 代理必须已同步到 `panel/.claude/agents/`（spec/43 CC-01）。

规则来源：`../spec/11-plans-entitlements.md`、`../spec/12-orders-payments.md`。

阶段一：并行构造反例（6 个 billing-verifier 代理，各负责一个方向，各自在独立 worktree 中）
1. 剩余价值公式：负值、超过实付、取整误差累积、多周期价格行、只按时间模式。
2. 价格锁定：涨价、降价、下架、到期后再购买、续费时更换周期。
3. 时序：到期瞬间付款、报价后用量或价格变化、并发续费与升级、排队降级后升级、迟到付款。
4. 流量：周期重置与续费交错、流量包消耗顺序、倍率换算。
5. 权限协调：套餐调整线路组、节点换组、权益到期、账号暂停后，增量结果与全量重算不一致的情况。
6. 退款与余额：退款后权益缩短、余额抵扣的并发、退款上限、返利冻结与作废。

每个反例必须是一个失败的测试，并注明违反规格的哪一句。

阶段二：复核（每个反例一个独立代理）
- 判断反例是实现错误、规格漏洞，还是测试本身错误。

输出：
- 汇总报告写入 `../review/billing-<日期>.md`（workspace 的 review 目录）。
- 确认为实现错误的测试，以 `//go:build adversarial` 标签合入 `adversarial_test.go`，不进入默认的 `make test`；CI 以非阻塞任务 `make test-adversarial` 运行（spec/42 ENG-07）。
- 规格漏洞按 `spec-change` 或规格修改流程处理。
