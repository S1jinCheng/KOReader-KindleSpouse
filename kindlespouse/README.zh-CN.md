# KOReader · KindleSpouse Edition

面向第一代 Kindle Scribe 的 KindleSpouse 定制版，基于官方 KOReader v2026.07.1。保留官方阅读引擎与原生设置，通过随源码维护的插件接入 KindleSpouse。

- 启动进入 Library 封面书架，自动汇总书籍目录及子目录；保留封面缓存、点击阅读和长按文件操作。
- 书架工具栏提供书名／作者／文件名搜索，全部／未读／在读／已读／收藏／书集入口，格式／作者／来源文件夹组合筛选，最近阅读／最近添加／书名／作者／进度排序，以及网格／列表切换。设置会保存；来源文件夹指设备目录，不等同于桌面端的网盘或书源账号。首次整理分批扫描，并在后台提取元数据；筛选与排序复用内存目录，只刷新书架区域。
- 底部只保留 Library、Notebook；顶部继续使用 KOReader 原有菜单和设置。
- Notebook 按书籍汇总高亮和文字笔记，显示计数、章节及日期；支持全文搜索，点击批注后在书中定位并保留返回历史。只读取当前批注主集合，避免把旧渲染模式的备份重复算入或复活删除内容。阅读体验菜单可独立关闭此页。
- Notebook 底部保留正常退出到 Kindle 的次要入口，随后点击系统的“笔记本”继续使用 Scribe 原生手写。当前不在 KOReader 内编辑 Amazon 笔记文件。
- 阅读体验菜单提供独立的简洁阅读菜单开关：返回书库、目录、书签、搜索、排版及“更多”，并支持进度跳转；统计插件可用时显示预计剩余时间。关闭后恢复上游菜单。
- 阅读体验菜单提供独立的高亮浮条开关；保留笔记、复制、查词和“更多”原版操作。单色屏只显示一个“高亮”按钮，并保留用户当前的高亮样式；彩色屏保留黄色、蓝色、紫色、橙色选项。
- 加入十款静态中文字体：Noto Serif CJK SC、Noto Sans CJK SC、霞鹜文楷、Fandol 仿宋、Fandol 宋体、Fandol 黑体、Fandol 楷体、霞鹜文楷 GB、霞鹜新致宋、霞鹜臻楷 GB。使用固定下载地址和 SHA-256 校验，随包保留原始许可。Fandol 字库较小，生僻字及繁体优先选 Noto。
- 继续使用 KindleSpouse 桌面端安装的独立同步组件，接收图书、同步资料、阅读进度与批注，并保留现有休眠封面配置。
- 可以在顶部菜单 KindleSpouse → 使用 KindleSpouse 主页关闭定制主页，恢复之前的启动和显示模式。菜单、状态窗口和书库支持中英文。
- 仅适配规范化版本 202607010000（v2026.07.1）。其他版本或界面安装失败时停用自定义界面，恢复原版界面；同步初始化独立运行。
- 同步由网络恢复、关闭书籍和批注变化触发，采用去抖、单任务与退避；联网时每 15 分钟检查图书与设置，阅读中延长至 30 分钟；阅读记录有变化时，在阅读中每 10 分钟执行一次完整同步。设备休眠时不承诺即时收书。手动同步仍可用。

## 下载和安装

从本仓库 Releases 下载预览安装包，或在 Actions 的 KindleSpouse Scribe 工作流下载构建产物。包名 `KindleSpouse-Scribe-Overlay.zip`，需要已安装官方 KOReader v2026.07.1。

先退出 KOReader，再将压缩包里的 `koreader` 与 `kindlespouse` 文件夹合并复制到 Kindle USB 根目录。重新打开 KOReader 后显示新书架。安装包不包含配对凭据，也不替换固件。完整步骤见 [INSTALL.txt](INSTALL.txt)。

初次使用无线同步时，在 [KindleSpouse 桌面应用](https://github.com/S1jinCheng/KindleSpouse)配对；此安装包本身不分发同步组件二进制。

## 构建

只生成主页与字体安装包，使用 Python 3.12 或更新版本：

```sh
python3 kindlespouse/build.py
```

安装包、SHA-256 文件和经校验的字体缓存生成在 `kindlespouse/build`，不提交二进制到 Git。

完整 KOReader 源码构建仅作为开发参考：分支构建可能带开发版本号，当前精确版本守卫不会自动把它视为已验证的官方版本。本轮预览请采用官方 v2026.07.1 加叠加包；完整定制二进制仍需单独适配和验收。

开发者可先按上游说明获取依赖和字体子模块，再准备额外字体，使用 KOReader 原有的 Kindle 构建目标：

```sh
make fetchthirdparty
python3 kindlespouse/build.py --prepare-fonts
make TARGET=kindle
```

插件位于 `plugins/kindlespouse.koplugin`，随 KOReader 的标准插件目录一起安装。字体准备步骤会将十款静态字体复制到 `resources/fonts/kindlespouse`，进入标准字体目录。

## 改进分支与验证

本轮改进按独立 PR 维护，尚未合并或安装到设备。详情见 [实施进度](IMPLEMENTATION.md)、[性能观测范围](PERFORMANCE.md)和[可选仓库迁移说明](MIGRATION.md)。迁移尚未执行。

安装包仅收录插件 Lua 模块、插件许可证、经校验的字体及许可和安装说明。验收会从全新目录解压安装包并启动真实插件，不依赖源码目录补齐缺失模块；书籍、笔记、配对文件和网盘授权不进入安装包。

## 验证与目前限制

工作流生成字体和主页安装包，并下载指纹固定的官方 x86_64 KOReader v2026.07.1，在隔离环境验证搜索、阅读状态／作者／格式／文件夹筛选、收藏、书集、排序、网格和列表、十款字体加载、双标签、原生标题栏、横竖屏与设置恢复。可在产物中查看运行时截图。

本地执行同一验收：

```sh
python3 kindlespouse/test_home.py --runtime /path/to/koreader
```

当前版本补齐了书架的基础筛选与管理入口。第一代 Scribe 上的触控、手写切换、休眠唤醒及大量图书时的性能仍需真机验证。当前包不替代 Kindle 的原生手写编辑器，不承诺与 KindleSpouse 桌面应用或 Apple Books 完全相同的外观和全部功能。

用户要求原有 Scribe 笔记继续编辑，因此没有用独立手写插件替换原始笔记。[Notebook 插件的存储实现](https://github.com/pierspad/notebook.koplugin/blob/fb66d7cfbf57ef67183795530f9bec014abdaffc/lua/documentstorage.lua)保存自己的页面／笔画结构；[Ink Away](https://github.com/EmirErtorer/ink-away.koplugin/tree/0c4a45a613a96cfb6ae87d8356695f93af71687f)也使用自己的笔记库并支持 PDF／图片导入。当前没有实现可验证的 Amazon 原生笔记格式回写。原有笔记仍需使用 Kindle 系统编辑，这项完整融合要求尚未完成。

上游版权及 AGPLv3 保留。字体分别采用 SIL OFL、带字体嵌入例外的 GPL 或 IPA Font License 1.0，原始许可和 Fandol 上游归档随包分发。字体文件保持原样；霞鹜新致宋的 IPA 许可与其固定版本信息一并提供。

## 运行时版本验收

已验证并启用界面：官方 v2026.07.1，规范化版本 `202607010000`。

v2026.07.2 尚未验证，白名单仍不包含该版本。[官方标签资源](https://github.com/koreader/koreader/releases/expanded_assets/v2026.07.2)只有源码归档，没有 AppImage。后续 nightly 与该标签包含的提交不同，不能替代精确版本验收。取得准确 AppImage 后，需要在该运行时通过完整测试，才能扩大白名单并更新兼容性断言。

以下入口先核对运行时实际版本，再串行执行 26 组验收，覆盖缓存启动截图与静默后台扫描、EPUB/PDF 阅读工具栏、目录增量扫描、主页返回、同步与中英文错误、单色和彩色高亮、笔记和解压后的安装包。各组日志及完整结果写入 `kindlespouse/build/runtime-checks`。当前 CI 使用同一入口。

```sh
python3 kindlespouse/test_runtime.py --runtime /path/to/koreader --fonts kindlespouse/build/cache --package kindlespouse/build/KindleSpouse-Scribe-Overlay.zip --expected-version 202607010000
```

`--expected-version` 只校验实际版本，不会修改运行时或绕过插件白名单。v2026.07.2 不能以 v2026.07.1 的运行时或改名的安装包代测。Scribe 真机触控、休眠和手写体验仍需单独验收。
