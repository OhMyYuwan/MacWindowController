# WinCtlManager

WinCtlManager 是一个原生 macOS 窗口布局管理工具，用于快速整理当前桌面上的窗口、保存和恢复桌面布局，并通过可视化 Workbench 调整分区、堆叠与窗口归属。

本项目使用 **ACP — Agent Content Protocol** 管理需求、计划与变更记录。

[English Version](./README_EN.md)

## Release v0.0.1

v0.0.1 是第一个可用 release，重点覆盖窗口基础控制、强制分区、堆叠标签栏、布局保存恢复和可视化操作台。

### 核心功能

- 基础窗口操作：列出、移动、缩放、平铺指定 App 窗口。
- 前台窗口快捷操作：把当前聚焦窗口平铺到指定位置，或放入左侧堆叠。
- 桌面布局：保存、列出、恢复、导入、导出、删除桌面布局。
- 强制分区：把桌面划分为多个 zone，并按分区规则重新分配窗口。
- 窗口堆叠：把同一区域内的多个窗口组织成类似标签页的 stack，只显示当前活动窗口。
- 可视化 Workbench：通过原生 AppKit 界面调整布局模式、分区比例、窗口路由、临时窗口和保存的布局。
- 堆叠标签栏样式：支持 Stack Tab GlassStyle 选择、预览、保存和应用。
- 不可控窗口处理：识别不适合被 AX 操作控制的窗口，避免它们被强制移动或归入分区。
- ACP 管理：项目内部保留 `Request -> Plan -> Change` 记录，便于持续演进。

## 系统要求

- macOS 13 或更高版本
- Swift Package Manager
- 辅助功能权限：首次控制窗口前，需要在系统设置中为运行的终端或 app 授予“辅助功能”权限

## 构建

```bash
cd tools/window-manager
swift build
```

运行测试：

```bash
cd tools/window-manager
swift test
```

## 打开 Workbench

```bash
cd tools/window-manager
swift run window-manager open-workbench
```

也可以直接编辑当前桌面：

```bash
swift run window-manager edit-current --name current_desktop
```

## 常用 CLI

列出窗口：

```bash
swift run window-manager list-windows --all
```

平铺指定窗口：

```bash
swift run window-manager tile-window --bundle-id com.google.Chrome --position left
```

平铺当前聚焦窗口：

```bash
swift run window-manager tile-frontmost --position right
```

保存当前桌面布局：

```bash
swift run window-manager save-desktop --name work
```

恢复桌面布局：

```bash
swift run window-manager apply-desktop --name work
```

打开并编辑保存的布局：

```bash
swift run window-manager edit-desktop --name work
```

查看完整命令：

```bash
swift run window-manager help
```

## 项目结构

```text
WinCtlManager/
├── tools/window-manager/        # Swift Package, CLI 和 AppKit Workbench
├── src/.acp/                    # ACP 项目状态与演进记录
├── acp-protocol/                # ACP 协议载荷，只读
├── AGENTS.md                    # Agent 工作说明
├── README.md                    # 中文 app README
└── README_EN.md                 # English app README
```

## 当前限制

- WinCtlManager 通过 macOS Accessibility API 控制第三方应用窗口。它可以移动、缩放、抬升窗口，但不能通过公开 API 把任意第三方窗口永久改成真正的系统级 always-on-top 窗口。
- 一些系统窗口、无稳定 bundle id 的窗口、特殊浮层或安全受限窗口可能只能被观察，不能被控制。
- 桌面/Space 切换与全屏空间行为仍需要谨慎处理。

## 开发流程

这是一个 ACP-managed 项目。所有面向功能的源码变更遵循：

```text
Request -> Plan -> Change
```

项目状态保存在 `src/.acp/`，协议载荷 `acp-protocol/` 视为只读。

## ACP 与相关链接

- Protocol Name：**ACP — Agent Content Protocol**
- ACP Handbook：[HANDBOOK.md](./HANDBOOK.md)
- ProtoCodeBase：[protocodebase.com](https://protocodebase.com)
- Agent Skills：[OhMyYuwan/ProtoCodeBase.Skill](https://github.com/OhMyYuwan/ProtoCodeBase.Skill)
