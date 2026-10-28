# Mint Todo

把待办放在桌面上的一张小便签。

支持 macOS 13 及以上，兼容 Apple Silicon 和 Intel Mac。提供简约、玻璃和复古纸签外观。

## 下载

### [↓ 直接下载 Mint Todo for Mac（DMG）](https://github.com/Liuuuuu17/mint-todo/releases/latest/download/MintTodo-macOS.dmg)

[版本说明](https://github.com/Liuuuuu17/mint-todo/releases/latest)

1. 打开下载的 DMG，将 **Mint Todo.app** 拖到“Applications”文件夹。
2. 如果已安装旧版，先退出，再替换一次。
3. 打开 App，输入事项并按回车，设置截止时间和重复方式。

GitHub 自动提供的“Source code (zip)”是源码包；安装应用请使用上方 DMG 下载链接。

**2.5 起更新前先显示说明。** 默认自动检查新版，发现更新时展示更新内容，由你选择安装、稍后提醒或跳过，确认后才下载和安装。设置 → 软件更新可以关闭自动检查或立即检查。

> 2.2 及更早版本需要先手动安装一次带更新功能的新版。应用使用本机签名，未经过 Apple 公证；首次在其他 Mac 上打开，可能出现系统来源确认提示。

## 桌面小组件试用版（独立下载）

<img src="https://github.com/Liuuuuu17/mint-todo/releases/download/widgets-trial-0.1.1/WidgetTrialIcon.png" alt="小组件试用版图标" width="140">

### [↓ 下载小组件试用版（DMG）](https://github.com/Liuuuuu17/mint-todo/releases/download/widgets-trial-0.1.1/MintTodo-Widgets-Trial.dmg)

[试用说明与反馈](https://github.com/Liuuuuu17/mint-todo/releases/tag/widgets-trial-0.1.1)

适用于 **macOS 14 及以上，兼容 Apple Silicon 和 Intel Mac**。这是独立的 **Mint Todo Widgets Trial.app**，可与正式版同时保留；任务与设置独立，正式版下载和自动更新通道保持不变。

| 尺寸 | 内容 |
| --- | --- |
| Small | 目标总体进度 |
| Medium | **全部未完成待办**，包含未来日期任务，最多显示三项，可打开完整列表 |
| Large | 多个目标、当前阶段及下一项任务 |

打开 DMG，把 Mint Todo Widgets Trial.app 拖到“Applications”文件夹，打开一次，再在桌面右键 → 编辑小组件 → 搜索 **Mint Todo · 试用**。使用你看到的手写 Mint Todo 与薄荷叶独立图标。

本机试用模式下，点击小圆圈会唤起试用 App 并同步完成状态。尚未经过 Apple Developer ID 签名或公证，其他 Mac 可能出现来源确认或阻止打开的提示；跨机器表现仍需测试。

菜单栏图标可区分两个版本：正式版是 **对勾 ✓**，小组件试用版是 **叶子**；两者均自动适配菜单栏的深浅颜色。

## 可以做什么

| 功能 | 说明 |
| --- | --- |
| 桌面便签 | 外框可切换直角或圆角、内部圆角；支持置顶、拖动与边缘缩放 |
| 收起圆点 | 纯色或细纸纹，可拖动，自动收起到最近的屏幕角落 |
| 待办与完成记录 | 完成后立即移入“已完成”，可恢复误点 |
| 子任务 | 分类内的任务可拆成子任务，独立勾选并显示进度 |
| 自然语言时间 | 输入“周三团建”“明天下午2:30到4:30培训”，提取时间并整理标题 |
| 截止与重复 | 一次性、每天、工作日或每 N 天重复 |
| 长期任务 | 目标 → 阶段 → 任务，同名分类、Markdown 说明与成果记录 |
| AI 计划 | 复制提示词、粘贴解析、自定义 API、拉取模型和预览修改 |
| 个性外观 | 复古纸签、玻璃、透明、实色、照片背景、自定义字体和字号 |
| 苹果提醒事项 | 同步指定列表；本机列表可用时无需开启 iCloud |

## 数据与更新

任务保存在本机 `~/Library/Application Support/OrbTodo/`。字体、背景和设置保存在应用外；替换或自动更新应用不会主动清除它们。可选 AI 的密钥保存在 macOS 钥匙串；只有主动使用 AI 功能时才发送相应计划内容。

自动更新从本仓库的 GitHub Releases 获取更新源和安装包，并校验签名。请从上方固定入口下载，不需要寻找某个功能分支里的安装包。

[详细使用说明与构建方法](https://github.com/Liuuuuu17/mint-todo/blob/v2.5.1/USER_GUIDE.md) · [开发文档](https://github.com/Liuuuuu17/mint-todo/blob/v2.5.1/DEVELOPMENT.md)

## 从源码构建

最新发布源码见 [v2.5.1](https://github.com/Liuuuuu17/mint-todo/tree/v2.5.1)。安装 Xcode 命令行工具后，在源码目录运行：

```sh
zsh build.sh
zsh test.sh
```

构建脚本会下载并校验固定版本的 Sparkle。发布签名需要原签名 Mac 的钥匙串，普通源码构建不需要私钥。第三方许可见发布源码中的 `THIRD_PARTY_NOTICES.md`。
