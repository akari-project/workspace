# <sing-box | xray-core> fork

上游：<URL>。本 fork 只为 node-agent 服务，许可证继承上游。

## 补丁范围（只允许三类）
1. 进程内增删用户
2. 连接计量钩子
3. 按凭据关闭会话

补丁清单与说明见 PATCHES.md，每个补丁一个独立提交。

## 同步上游
使用 workspace 的 `core-upgrade` Skill。tag 格式：`<上游版本>-panel.<序号>`。
