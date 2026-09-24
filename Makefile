# SPDX-License-Identifier: Apache-2.0
#
# workspace 的检查（spec/42 42.2）。本地与 CI 执行同一目标：make ci。
# REUSE lint 由 CI 的 reuse 任务执行（需要 reuse 工具）。

.DEFAULT_GOAL := ci
.PHONY: ci check-spdx licenses test-hooks

ci: check-spdx licenses test-hooks

# 已跟踪文件前两行之内必须有 SPDX 标识（CONV-25）；REUSE.toml 中登记的文件与 LICENSES/ 除外。
check-spdx:
	python3 scripts/check_spdx.py

# 依赖许可证扫描（Apache-2.0 仓库的允许清单）。本仓库目前没有代码依赖，扫描为占位；
# 加入 go.mod 或 package.json 时在此补充对应的扫描。
licenses:
	@if [ -f go.mod ] || [ -f package.json ]; then echo "licenses: 发现依赖清单，需要补充扫描"; exit 1; fi
	@echo "licenses: 没有依赖，跳过"

# Claude Code hooks 的自动化测试（spec/43 43.3，M0-08 验收 1）；需要 jq 与 gofmt。
test-hooks:
	scripts/hooks/test-hooks.sh
