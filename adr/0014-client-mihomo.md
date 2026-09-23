# ADR 0014：自研客户端使用 mihomo 内核

- 状态：已接受
- 日期：2026-09

## 背景
自研客户端需要一个嵌入式代理内核。候选为 sing-box 与 mihomo，两者均为 GPL-3.0，均支持本项目的 7 种协议。

## 决定
客户端内嵌 mihomo。客户端从 `/v1/me/configuration` 取得结构化配置，在本地生成 mihomo 配置；转换逻辑与控制面的 mihomo 导出适配器共用 golden 测试数据。

## 影响
- 客户端仍为 GPL-3.0-or-later。
- mihomo 文档声明不兼容 Xray-core v26.7.11 及以上服务端的 Reality 行为：面向自研客户端的 Reality 入站应放在 sing-box 内核节点上，后台在 Xray 节点配置 Reality 时给出警告。
- mihomo 不支持 AnyTLS 与 Reality 组合，本项目 AnyTLS 使用普通 TLS。
