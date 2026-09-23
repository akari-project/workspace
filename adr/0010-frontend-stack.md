# ADR 0010：前端技术栈

- 状态：提议
- 日期：2026-09

## 背景
见 spec/41。团队熟悉度决定最终选择。

## 决定
React + TypeScript + Vite + TanStack Router/Query + openapi-fetch + Radix + Tailwind + i18next；pnpm workspace 四个包。

## 影响
若改为 Vue，只替换框架层，SDK 与目录结构不变。
