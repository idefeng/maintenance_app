# 本地自动整理与清理工具

这个仓库当前包含一个用于 macOS 的本地文件整理工具，相关代码和配置已收拢到 [`/Users/idefeng/Documents/work/tools/file_organizer`](/Users/idefeng/Documents/work/tools/file_organizer)。
同时新增了一个用于扫描已卸载应用残留文件的工具，相关代码位于 [`/Users/idefeng/Documents/work/tools/app_cleanup`](/Users/idefeng/Documents/work/tools/app_cleanup)。
磁盘空间清理工具位于 [`/Users/idefeng/Documents/work/tools/disk_cleanup`](/Users/idefeng/Documents/work/tools/disk_cleanup)，现在也是本地维护任务的统一入口：可定期清理 `Documents/work` 和 `DEV` 下已经确认的可重建占用，附带登录项只读报告，并可复用文件整理工具的整理规则。
macOS 原生可视化工具位于 [`/Users/idefeng/Documents/work/tools/maintenance_app`](/Users/idefeng/Documents/work/tools/maintenance_app)，用于通过 SwiftUI 查看报告并手动触发统一维护脚本。

## macOS 原生维护工具

第一版是 SwiftPM 形式的 SwiftUI App，不依赖 Xcode 工程文件。当前机器只有 Command Line Tools 时也可以构建和运行。

```bash
cd /Users/idefeng/Documents/work/tools/maintenance_app
swift run MaintenanceCoreChecks
swift build
swift run MaintenanceApp
/bin/zsh /Users/idefeng/Documents/work/tools/maintenance_app/scripts/build_app_bundle.sh
/bin/zsh /Users/idefeng/Documents/work/tools/maintenance_app/scripts/build_app_bundle.sh --install
open /Users/idefeng/Documents/work/tools/maintenance_app/dist/MaintenanceApp.app
open /Applications/MaintenanceApp.app
```

界面包含：

- 总览：展示健康检查、最近报告、待清理项、预计释放空间、文件整理动作和登录项复核数量
- 磁盘清理：展示统一脚本报告中的清理候选项，并用环形图展示当前磁盘总量、已用和可用空间
- 文件整理：展示来源目录、整理动作、待处理目录和跳过条目，并可从 App 添加额外整理路径
- 登录项：展示重复显示名、登录项明细、应用图标和建议动作
- 定时任务：展示 `com.idefeng.disk-cleanup`、`com.idefeng.file-organizer`、`com.idefeng.app-cleanup` 的图标、plist 与计划时间

磁盘清理页支持按路径、类别、原因、状态和类别筛选候选项，并可打开单项详情查看路径、风险、大小、状态与错误信息。登录项页支持按名称、开发者、identifier、路径和建议动作搜索，并可在“全部、残留、自有、重复、复核”范围间切换；单项详情会展示 identifier、路径、分类原因和建议动作。

当前界面已按 Figma 设计稿落地为更接近 macOS 原生工具的布局：左侧固定侧边栏、主内容区约束宽度、标题区集中放置运行和报告操作、指标保持轻量文本排版，定时任务与日志预览采用紧凑双栏结构。

工具按钮：

- `刷新`：重新读取 `tools/disk_cleanup/runtime/reports/latest.json`
- `打开报告`：用默认 App 打开统一维护报告 `latest.json`
- `复制摘要`：把最近报告的 Markdown 摘要复制到剪贴板，方便发给人工复核
- `导出摘要`：把最近报告的 Markdown 摘要写入 `tools/disk_cleanup/runtime/reports/` 并在 Finder 中选中
- `运行详情`：打开最近一次预览、维护或重新安装任务的命令、退出码、stdout 和 stderr
- `扫描`：执行 `disk_cleanup.py --login-items --organize-files --json`，只生成报告和健康检查，不删除文件
- `执行保守维护`：执行 `disk_cleanup.py --apply --login-items --organize-files --json`

第一版不会删除登录项，也不会自动处理系统级 LaunchAgent/Daemon；登录项页面只展示报告和人工复核建议。

定时任务页每个任务提供：

- `打开 plist`：打开当前安装到 `~/Library/LaunchAgents` 的 plist
- `查看日志`：打开对应工具的 `runtime/logs/` 目录
- `预览日志`：在 App 内读取并展示对应日志目录中最近的日志文件，较大的日志只显示尾部内容
- `重新安装`：调用对应工具的 `scripts/install_launch_agent.sh`

总览的健康检查会集中提示以下问题：

- 磁盘可用空间低于阈值或接近警戒线
- 最近报告缺失、过期或包含清理失败项
- 登录项中存在疑似卸载残留或大量人工复核项
- 文件整理仍有待人工处理的子目录
- 用户添加的整理路径不存在或不是目录
- 本仓库维护用 LaunchAgent 未安装、命令缺失或报告产物过期

文件整理页添加的额外整理路径会写入：

- `/Users/idefeng/Documents/work/tools/file_organizer/runtime/config/source-rules.json`

额外路径默认只整理第一层，和现有 `Desktop`、`Downloads`、`Documents` 规则一致；统一维护入口 `disk_cleanup.py --organize-files` 和单独的 `file_organizer.py` 都会读取这份配置。

构建脚本会生成可双击启动的 App：

- App 路径：`/Users/idefeng/Documents/work/tools/maintenance_app/dist/MaintenanceApp.app`
- 安装路径：`/Applications/MaintenanceApp.app`
- Bundle ID：`com.idefeng.maintenanceapp`
- 签名方式：本机 ad-hoc codesign
- 图标：构建时由 `scripts/generate_app_icon.py` 生成 `MaintenanceApp.icns`

`dist/` 是构建产物目录，已加入 `.gitignore`。

## 整理规则

- 来源目录固定为：`/Users/idefeng/Desktop`、`/Users/idefeng/Downloads`、`/Users/idefeng/Documents`
- 三个来源目录都只处理第一层文件，不递归进入子目录
- 发现普通子目录时，会把它们记录到待处理清单，供后续人工处理
- 应用程序类文件会移动到 `A-项目管理/其他信息/软件安装包`
- 当前应用程序类文件后缀包括：`.app`、`.dmg`、`.pkg`、`.mpkg`、`.spk`、`.iso`、`.zip`、`.rar`、`.7z`、`.tar`、`.gz`、`.bz2`、`.xz`
- 文档类文件会先按文件名关键词依次归档到 `work` 下对应项目目录
- 如果文档文件未命中项目关键词，则会统一进入 `A-项目管理/其他信息`
- 普通非文档文件当前不参与自动移动，会留在原目录并写入运行报告的跳过清单
- Finder 生成的系统元数据文件如 `.DS_Store`、`.localized` 会继续跳过，不参与整理
- `A-项目管理/其他信息/软件安装包` 与 `A-项目管理/其他信息` 这类工具自身管理目录不会写入待处理子目录清单

## 手动运行

```bash
python3 /Users/idefeng/Documents/work/tools/file_organizer/scripts/file_organizer.py --dry-run
python3 /Users/idefeng/Documents/work/tools/file_organizer/scripts/file_organizer.py
python3 /Users/idefeng/Documents/work/tools/file_organizer/scripts/file_organizer.py --json
/bin/zsh /Users/idefeng/Documents/work/tools/file_organizer/scripts/run_file_organizer.sh
/bin/zsh /Users/idefeng/Documents/work/tools/file_organizer/scripts/run_file_organizer.sh --dry-run
python3 /Users/idefeng/Documents/work/tools/disk_cleanup/scripts/disk_cleanup.py --skip-disk-cleanup --organize-files
python3 /Users/idefeng/Documents/work/tools/disk_cleanup/scripts/disk_cleanup.py --skip-disk-cleanup --organize-files --apply
```

## 运行产物

- JSON 报告：`/Users/idefeng/Documents/work/tools/file_organizer/runtime/reports/latest.json`
- 待处理子目录清单：`/Users/idefeng/Documents/work/tools/file_organizer/runtime/reports/pending-directories-latest.json`
- 文本日志：`/Users/idefeng/Documents/work/tools/file_organizer/runtime/logs/`，每次执行会生成一个 `file-organizer-时间戳.log`
- `launchd` 配置模板：[`/Users/idefeng/Documents/work/tools/file_organizer/launchd/com.idefeng.file-organizer.plist`](/Users/idefeng/Documents/work/tools/file_organizer/launchd/com.idefeng.file-organizer.plist)
- 安装脚本：[`/Users/idefeng/Documents/work/tools/file_organizer/scripts/install_launch_agent.sh`](/Users/idefeng/Documents/work/tools/file_organizer/scripts/install_launch_agent.sh)

当前版本的整理报告包含来源目录维度统计、待处理子目录数量和跳过条目数量；普通非文档文件会出现在 `skipped_entries` 中。待处理目录清单也会带上生成时间与总数元数据。

当前内置文档关键词规则顺序如下：

- `托育` -> `A-项目管理/A-国家卫健委/1-能力建设和继续教育中心/1-资格认证处/托育项目`
- `睡眠` -> `A-项目管理/A-国家卫健委/1-能力建设和继续教育中心/睡眠医学人才`
- `继续医学教育` 或 `CME` -> `A-项目管理/A-国家卫健委/1-能力建设和继续教育中心/继续医学教育管理平台`
- `培训统筹` -> `A-项目管理/A-国家卫健委/1-能力建设和继续教育中心/培训统筹办公室`
- `可验证` -> `A-项目管理/A-国家卫健委/1-能力建设和继续教育中心/可验证自学`
- `中医药` -> `A-项目管理/A-国家卫健委/2-中医药管理局`
- `工业互联网` -> `A-项目管理/G-工业互联网研究院`
- `博奥教育` -> `A-项目管理/其他信息/公司信息`
- 未命中 -> `A-项目管理/其他信息`

## 安装 launchd

```bash
/bin/zsh /Users/idefeng/Documents/work/tools/file_organizer/scripts/install_launch_agent.sh
```

该任务会由 `launchd` 在每天 13:00 通过 `osascript` 唤起 `Terminal` 执行 `run_file_organizer.sh`。这样做是为了绕开后台 `launchd` 直接访问 `Desktop`、`Documents`、`Downloads` 时可能遇到的 macOS 权限限制；真正的整理逻辑已委托给统一入口 `disk_cleanup.py --skip-disk-cleanup --organize-files --apply`，并把输出写入 `runtime/logs/`。

如果定时执行没有生效，优先检查：

- `Terminal` 是否已被 macOS 允许访问 `Desktop`、`Documents`、`Downloads`
- `launchctl print gui/$(id -u)/com.idefeng.file-organizer` 是否显示已加载
- `tools/file_organizer/runtime/logs/` 中是否生成新的 `file-organizer-时间戳.log`

## 应用残留扫描

该工具用于扫描 macOS 已卸载应用在用户目录中的候选残留文件，默认只生成报告；启用 `--apply` 时，会按规则分级只删除低风险缓存/日志类残留。

### 手动运行

```bash
python3 /Users/idefeng/Documents/work/tools/app_cleanup/scripts/app_cleanup.py LetsVPN
python3 /Users/idefeng/Documents/work/tools/app_cleanup/scripts/app_cleanup.py LetsVPN --json
python3 /Users/idefeng/Documents/work/tools/app_cleanup/scripts/app_cleanup.py LetsVPN --apply
python3 /Users/idefeng/Documents/work/tools/app_cleanup/scripts/app_cleanup.py LetsVPN --report-path /tmp/letsvpn-cleanup.json
```

### 扫描范围

- `~/Applications`
- `~/Library/Application Support`
- `~/Library/Caches`
- `~/Library/HTTPStorages`
- `~/Library/Logs`
- `~/Library/Preferences`
- `~/Library/Saved Application State`
- `~/Library/LaunchAgents`
- `~/Library/WebKit`
- `~/Library/Containers`
- `~/Library/Group Containers`

### 规则分级清理

- 自动删除：`~/Library/Caches`、`~/Library/HTTPStorages`、`~/Library/Logs`、`~/Library/Saved Application State`
- 只报告不删除：`~/Applications`、`~/Library/Application Support`、`~/Library/Preferences`、`~/Library/LaunchAgents`、`~/Library/WebKit`、`~/Library/Containers`、`~/Library/Group Containers`
- 系统设置里的 VPN 配置、Network Extension、登录项等高风险项不会自动删除，只会在报告中提示人工检查

### 运行产物

- JSON 报告默认输出到 `tools/app_cleanup/runtime/reports/`
- `launchd` 日志输出到 `tools/app_cleanup/runtime/logs/`

### 定时运行

`launchd` 模板位于 [`/Users/idefeng/Documents/work/tools/app_cleanup/launchd/com.idefeng.app-cleanup.plist`](/Users/idefeng/Documents/work/tools/app_cleanup/launchd/com.idefeng.app-cleanup.plist)，配置为每周五东京时间 `15:00` 运行一次，对应北京时间 `14:00`。
该任务会通过 `osascript` 唤起 `Terminal` 执行清理脚本，用来绕开后台进程直接读取 `Documents` 时可能遇到的 macOS 权限限制。

安装示例：

```bash
mkdir -p ~/Library/LaunchAgents
cp /Users/idefeng/Documents/work/tools/app_cleanup/launchd/com.idefeng.app-cleanup.plist ~/Library/LaunchAgents/
launchctl unload ~/Library/LaunchAgents/com.idefeng.app-cleanup.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/com.idefeng.app-cleanup.plist
```

也可以使用安装脚本：

```bash
/bin/zsh /Users/idefeng/Documents/work/tools/app_cleanup/scripts/install_launch_agent.sh
```

## 磁盘空间清理

该工具用于清理两类已经验证过的空间占用：

- `/Users/idefeng/Documents/work/.git/objects/pack/tmp_pack_*` 这类 Git 临时 pack 垃圾
- `/Users/idefeng/DEV` 下可重建的开发依赖、虚拟环境和构建缓存，例如 `node_modules`、`.venv`、`.next`、`.cache`、`.pytest_cache`、`.vite`、`.expo`、`test-results`、`dist` 和安全的 `build` 目录

工具默认只生成预览报告，不会删除文件；必须传入 `--apply` 才会真正清理。清理前会检查候选目录中是否包含 Git 已跟踪文件，包含时会跳过并写入报告，避免误删源码资产。

### 手动运行

```bash
python3 /Users/idefeng/Documents/work/tools/disk_cleanup/scripts/disk_cleanup.py --json
python3 /Users/idefeng/Documents/work/tools/disk_cleanup/scripts/disk_cleanup.py --login-items
python3 /Users/idefeng/Documents/work/tools/disk_cleanup/scripts/disk_cleanup.py --organize-files
python3 /Users/idefeng/Documents/work/tools/disk_cleanup/scripts/disk_cleanup.py --skip-disk-cleanup --organize-files
python3 /Users/idefeng/Documents/work/tools/disk_cleanup/scripts/disk_cleanup.py --apply
python3 /Users/idefeng/Documents/work/tools/disk_cleanup/scripts/disk_cleanup.py --apply --login-items --organize-files
python3 /Users/idefeng/Documents/work/tools/disk_cleanup/scripts/disk_cleanup.py --apply --include-assets
```

其中：

- `--json`：输出完整预览报告
- `--login-items`：附带生成 macOS“登录项与后台活动”的只读报告，用于定位重复显示项、LaunchAgent/Daemon 来源和疑似卸载残留
- `--organize-files`：同时运行文件整理规则；未传 `--apply` 时只演练，传入 `--apply` 时会实际移动命中的文件
- `--skip-disk-cleanup`：跳过磁盘缓存扫描与清理，仅运行 `--organize-files`、`--login-items` 等附加功能，供每日文件整理任务使用
- `--apply`：执行保守清理，不清理业务资产和 release 交付包
- `--include-assets`：在手动执行时额外清理 `/Users/idefeng/DEV/ETLChina/BAResoucesSystem/course_assets` 与 `/Users/idefeng/DEV/ETLChina/大资源平台/automation/release`

### 登录项只读报告

`--login-items` 会调用 `sfltool dumpbtm` 并扫描以下 plist 目录：

- `~/Library/LaunchAgents`
- `/Library/LaunchAgents`
- `/Library/LaunchDaemons`

报告会写入 `login_items` 字段，包含重复显示名、来源 plist、可执行文件路径、分类和建议动作。该功能不会删除登录项，也不会修改系统设置。报告中的 `own_automation` 表示本仓库安装的本地自动化任务，建议保留；`possible_remnant` 表示疑似卸载残留，建议人工复核；`system_background_item` 表示系统级 LaunchAgent/Daemon，通常需要管理员权限和明确卸载策略后再处理。

### 运行产物

- JSON 报告默认输出到 `tools/disk_cleanup/runtime/reports/`
- 最新报告固定写入 `tools/disk_cleanup/runtime/reports/latest.json`
- `launchd` 日志目录为 `tools/disk_cleanup/runtime/logs/`

### 定时运行

`launchd` 模板位于 [`/Users/idefeng/Documents/work/tools/disk_cleanup/launchd/com.idefeng.disk-cleanup.plist`](/Users/idefeng/Documents/work/tools/disk_cleanup/launchd/com.idefeng.disk-cleanup.plist)，配置为每周六东京时间 `10:30` 运行一次保守清理。

安装命令：

```bash
/bin/zsh /Users/idefeng/Documents/work/tools/disk_cleanup/scripts/install_launch_agent.sh
```

该定时任务只会调用：

```bash
/bin/zsh /Users/idefeng/Documents/work/tools/disk_cleanup/scripts/run_disk_cleanup.sh
```

因此不会自动清理 `course_assets` 和 `automation/release`，但会执行保守磁盘清理、文件整理，并随报告附带一次登录项只读扫描。需要清理这两类目录时，应手动执行带 `--include-assets` 的命令。
