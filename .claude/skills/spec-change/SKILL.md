---
name: spec-change
description: 修改节点协议（proto）或客户端接口（OpenAPI）时使用。覆盖从改规范、兼容检查、能力位、打 tag 到各仓升级依赖的完整流程。
---
# 修改协议或接口

## 步骤
1. **确认规格**：在 `spec/20`（节点协议）或 `spec/30`（客户端接口）中找到对应章节。规格没有覆盖的改动，先更新规格文档。
2. **改 panel-spec**
   - proto：只新增字段与消息；删除的字段编号写入 `reserved`；新行为对应一个新的 `Capabilities` 字段。
   - OpenAPI：遵守 `spec/02` 命名约定；新增字段必须可选；新增错误码同步到 `spec/02` 的错误表。
3. **检查**：在 `panel-spec/` 运行
   - `buf lint && buf breaking --against '.git#branch=main'`
   - `npx @redocly/cli lint openapi/client/v1.yaml`
4. **审查**：调用 `protocol-reviewer` 子代理。
5. **打 tag**：合并后打 `vX.Y.Z`（新增字段为小版本，修复为补丁版本）。
6. **各仓升级**：分别在 `panel` 与 `node-agent` 更新依赖到新 tag，运行 `make gen && make test`。新功能在能力位为假时必须保持旧行为。
7. **兼容矩阵**：更新 `panel/README.md` 与 `node-agent/README.md` 中的兼容表。

## 禁止
- 修改已有字段的编号、类型或语义。
- 在同一个提交中同时修改 panel-spec 和其他仓库。
