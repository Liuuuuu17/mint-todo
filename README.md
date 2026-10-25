# Mint Todo

把待办放在桌面上的一张小便签。

支持 macOS 13 及以上，兼容 Apple Silicon 和 Intel Mac。提供简约、玻璃和复古纸签外观。

## 下载

### [↓ 直接下载 Mint Todo for Mac](https://github.com/Liuuuuu17/mint-todo/releases/latest/download/MintTodo-macOS.zip)

[版本说明](https://github.com/Liuuuuu17/mint-todo/releases/latest) · [完整项目包](https://github.com/Liuuuuu17/mint-todo/releases/latest/download/MintTodo-project.zip)

1. 解压下载的 ZIP，将 **Mint Todo.app** 拖入“应用程序”。
2. 如果已安装旧版，先退出，再替换一次。
3. 打开 App，输入事项并按回车，设置截止时间和重复方式。

**2.3 起支持自动更新。** 默认自动检查和下载新版，退出后安装，不需要每次重新下载、拖入替换。设置 → 软件更新可以关闭自动更新或立即检查。

> 2.2 及更早版本需要先手动安装一次带更新功能的新版。应用使用本机签名，未经过 Apple 公证；首次在其他 Mac 上打开，可能出现系统来源确认提示。

## 可以做什么

| 功能 | 说明 |
| --- | --- |
| 桌面便签 | 直角外框、内部圆角；支持置顶、拖动与边缘缩放 |
| 收起圆点 | 纯色或细纸纹，可拖动，自动收起到最近的屏幕角落 |
| 待办与完成记录 | 完成后立即移入“已完成”，可恢复误点 |
| 子任务 | 分类内的任务可拆成子任务，独立勾选并显示进度 |
| 截止与重复 | 一次性、每天、工作日或每 N 天重复 |
| 长期任务 | 目标 → 阶段 → 任务，同名分类、Markdown 说明与成果记录 |
| AI 计划 | 复制提示词、粘贴解析、自定义 API、拉取模型和预览修改 |
| 个性外观 | 复古纸签、玻璃、透明、实色、照片背景、自定义字体和字号 |
| 苹果提醒事项 | 同步指定列表；本机列表可用时无需开启 iCloud |

## 数据与更新

任务保存在本机 `~/Library/Application Support/OrbTodo/`。字体、背景和设置保存在应用外；替换或自动更新应用不会主动清除它们。可选 AI 的密钥保存在 macOS 钥匙串；只有主动使用 AI 功能时才发送相应计划内容。

自动更新从本仓库的 GitHub Releases 获取更新源和安装包，并校验签名。请从上方固定入口下载，不需要寻找某个功能分支里的 ZIP。

[详细使用说明与构建方法](https://github.com/Liuuuuu17/mint-todo/blob/v2.4/USER_GUIDE.md) · [开发文档](https://github.com/Liuuuuu17/mint-todo/blob/v2.4/DEVELOPMENT.md)

## 从源码构建

最新发布源码见 [v2.4](https://github.com/Liuuuuu17/mint-todo/tree/v2.4)。安装 Xcode 命令行工具后，在源码目录运行：

```sh
zsh build.sh
zsh test.sh
```

构建脚本会下载并校验固定版本的 Sparkle。发布签名需要原签名 Mac 的钥匙串，普通源码构建不需要私钥。第三方许可见发布源码中的 `THIRD_PARTY_NOTICES.md`。
