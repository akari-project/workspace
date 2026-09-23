---
name: e2e-scenario
description: 编写跨仓端到端测试时使用：启动 PostgreSQL、Valkey、控制面与模拟或真实 Agent，按业务流程断言。
---
# 编写端到端测试

## 环境
- 使用 testcontainers-go 启动 `postgres:18` 与 `valkey/valkey:9`，运行全部迁移。
- 控制面以进程内方式启动（`server.NewForTest(cfg)`），时钟使用可注入的假时钟，便于测试到期与周期重置。
- 模拟 Agent：`e2e/fakeagent`，可编程控制断线、延迟、重复发送、丢包。
- 真实 Agent：在容器中运行 `node-agent`，入站使用回环地址，客户端用对应内核的出站拨号。

## 用例结构
```go
func TestScenario_ExpireReturnsToFree(t *testing.T) {
    env := e2e.Start(t)                       // 容器、控制面、假时钟
    acc := env.SignupVerified(t)
    node := env.EnrollNode(t, e2e.FakeAgent)  // 完成接入与入站配置
    env.GrantPlan(t, acc, "basic", 30*day)
    node.WaitCred(t, acc)                     // 节点收到凭据
    env.Clock.Advance(30*day + time.Second)
    node.WaitCredRemoved(t, acc)              // 到期后凭据收回
    env.AssertEntitlementStatus(t, acc, "none")
}
```

## 要求
- 每个 backlog 验收标准至少一个用例，用例名引用任务编号，例如 `TestM1_07_...`。
- 不使用 `time.Sleep` 等待，一律用带超时的等待辅助函数。
- 失败时输出控制面与 Agent 的最近日志片段。
