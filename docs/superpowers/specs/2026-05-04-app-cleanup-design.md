# macOS 应用残留清理脚本设计

## 背景

用户在 macOS 上卸载应用后，常会遗留用户级配置、缓存、日志、启动项等文件。本次目标是在稳定扫描和结构化报告基础上，提供“规则分级清理”的半自动模式：只自动删除低风险残留，高风险项继续保守报告。

## 目标

- 提供一个命令行脚本，输入应用名后扫描常见用户级残留目录
- 输出终端可读结果和 JSON 报告
- 默认只读，不执行删除
- 提供 `--apply` 模式，只删除低风险白名单目录中的命中项
- 设计上支持后续扩展到“确认删除”模式

## 非目标

- 不修改系统设置
- 不处理系统级目录下需要提权的位置
- 不自动删除偏好设置、容器、LaunchAgents、网络扩展等高风险项
- 不保证识别所有应用残留，只保证结果可解释且尽量保守

## 目录结构

- `tools/app_cleanup/scripts/app_cleanup.py`
- `tools/app_cleanup/tests/test_app_cleanup.py`
- `tools/app_cleanup/launchd/com.idefeng.app-cleanup.plist`
- `tools/app_cleanup/runtime/reports/`
- `tools/app_cleanup/runtime/logs/`

## 命令行接口

命令示例：

```bash
python3 /Users/idefeng/Documents/work/tools/app_cleanup/scripts/app_cleanup.py LetsVPN
python3 /Users/idefeng/Documents/work/tools/app_cleanup/scripts/app_cleanup.py LetsVPN --json
python3 /Users/idefeng/Documents/work/tools/app_cleanup/scripts/app_cleanup.py LetsVPN --apply
python3 /Users/idefeng/Documents/work/tools/app_cleanup/scripts/app_cleanup.py LetsVPN --report-path /tmp/letsvpn-cleanup.json
```

参数：

- 位置参数 `app_name`：应用名，例如 `LetsVPN`
- 可选参数 `--json`：将完整报告输出到标准输出
- 可选参数 `--report-path`：指定报告输出路径
- 可选参数 `--apply`：执行低风险白名单清理动作

## 扫描范围与风险分级

脚本扫描当前用户目录下的常见残留位置，并按风险分级：

- `~/Applications`：只报告
- `~/Library/Application Support`：只报告
- `~/Library/Caches`：允许自动删除
- `~/Library/HTTPStorages`：允许自动删除
- `~/Library/Logs`：允许自动删除
- `~/Library/Preferences`：只报告
- `~/Library/Saved Application State`：允许自动删除
- `~/Library/LaunchAgents`：只报告
- `~/Library/WebKit`：只报告
- `~/Library/Containers`：只报告
- `~/Library/Group Containers`：只报告

脚本应跳过不存在的目录，并在报告中保留扫描状态。

## 匹配策略

### 1. 规范化名称匹配

将输入应用名规范化后生成基础关键词，例如：

- 原始名称：`LetsVPN`
- 小写名称：`letsvpn`
- 去分隔符名称：例如 `lets-vpn`、`lets_vpn` 归并为 `letsvpn`

### 2. 路径名匹配

对目录名和文件名执行保守匹配：

- 完整包含规范化名称
- 忽略大小写
- 对 `-`、`_`、空格差异不敏感

### 3. 反向域名前缀匹配

针对偏好设置和容器目录，补充常见 bundle id 风格匹配：

- `com.<name>*`
- `*.<name>*`

例如 `com.letsvpn.client.plist` 应被识别。

### 4. 显式规则扩展

脚本内部保留一小组可扩展规则入口，用于未来为特定应用补充别名，例如：

- `LetsVPN` 可扩展到 `letsvpn`

第一版不做外部规则文件，避免过度设计。

## 清理分级策略

### safe_delete

只允许在以下低风险目录自动删除：

- `~/Library/Caches`
- `~/Library/HTTPStorages`
- `~/Library/Logs`
- `~/Library/Saved Application State`

### report_only

以下目录即使命中，也只报告不删除：

- `~/Applications`
- `~/Library/Application Support`
- `~/Library/Preferences`
- `~/Library/LaunchAgents`
- `~/Library/WebKit`
- `~/Library/Containers`
- `~/Library/Group Containers`

### skip

未归类目录、缺少权限、目标已不存在等情况标记为 `skip` 或失败状态，保留在报告中供人工处理。

## 输出报告

报告为 JSON，包含：

- `app_name`
- `generated_at`
- `cleanup_mode`
- `scan_roots`
- `matches`
- `match_count`
- `action_summary`

单条命中至少包含：

- `path`
- `category`
- `name`
- `match_reason`
- `path_type`
- `risk_level`
- `planned_action`
- `action_status`

其中 `category` 是扫描根目录对应的逻辑分类，`match_reason` 用于说明是名称匹配还是 bundle 风格匹配。

## 终端输出

默认终端输出包含：

- 扫描的应用名
- 当前模式（`scan` 或 `apply`）
- 扫描目录数量
- 命中数量
- 每条命中的分类、路径、计划动作和执行状态
- 动作统计
- 报告文件输出位置

如果无命中，也应明确输出“未发现候选残留”。

## 测试策略

测试重点放在纯函数与临时目录扫描：

- 名称规范化
- 路径匹配逻辑
- 扫描结果去重
- 风险分级
- 低风险删除与高风险保留
- JSON 报告结构

不依赖真实用户目录，避免测试污染本机环境。

## 定时运行

提供 `launchd` 模板，每周五东京时间 15:00 运行一次，对应北京时间 14:00。考虑到后台 `launchd` 直接访问 `Documents` 目录会遇到 macOS 权限限制，任务通过 `osascript` 唤起 `Terminal` 执行。实际命令如下：

```bash
python3 /Users/idefeng/Documents/work/tools/app_cleanup/scripts/app_cleanup.py LetsVPN --apply
```

系统设置中残留的 VPN 配置、Network Extension、登录项等不纳入自动删除范围，只在报告中提示人工核查。

## 后续演进

后续可在此基础上增加：

- `--interactive`
- 外部规则文件
- 扫描系统级目录
- 按应用清理模板输出 shell 命令
