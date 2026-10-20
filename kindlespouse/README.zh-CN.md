# KOReader · KindleSpouse Edition

面向第一代 Kindle Scribe 的 KindleSpouse 定制版，基于官方 KOReader v2026.07.1。保留官方阅读引擎与原生设置，通过随源码维护的插件接入 KindleSpouse。

- 启动进入 Library 封面书架，自动汇总书籍目录及子目录；保留封面缓存、点击阅读和长按文件操作。
- 书架工具栏提供书名／作者／文件名搜索，全部／未读／在读／已读／收藏／书集入口，格式／作者／来源文件夹组合筛选，最近阅读／最近添加／书名／作者／进度排序，以及网格／列表切换。设置会保存；来源文件夹指设备目录，不等同于桌面端的网盘或书源账号。首次整理会读取并缓存书籍元数据。
- 底部只保留 Library、Notebook；顶部继续使用 KOReader 原有菜单和设置。
- Notebook 提供正常退出到 Kindle 的入口，随后点击系统的“笔记本”继续使用 Scribe 原生手写。当前不支持一键直达指定原生笔记本，也不在 KOReader 内编辑 Amazon 笔记文件。
- 加入十款静态中文字体：Noto Serif CJK SC、Noto Sans CJK SC、霞鹜文楷、Fandol 仿宋、Fandol 宋体、Fandol 黑体、Fandol 楷体、霞鹜文楷 GB、霞鹜新致宋、霞鹜臻楷 GB。使用固定下载地址和 SHA-256 校验，随包保留原始许可。Fandol 字库较小，生僻字及繁体优先选 Noto。
- 继续使用 KindleSpouse 桌面端安装的独立同步组件，接收图书、同步资料、阅读进度与批注，并保留现有休眠封面配置。
- 可以在顶部菜单 KindleSpouse → Use KindleSpouse home 关闭定制主页，恢复之前的启动和显示模式。

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

构建完整 KOReader 时，先按上游说明获取依赖和字体子模块，再准备额外字体，然后使用 KOReader 原有的 Kindle 构建目标：

```sh
make fetchthirdparty
python3 kindlespouse/build.py --prepare-fonts
make TARGET=kindle
```

插件位于 `plugins/kindlespouse.koplugin`，随 KOReader 的标准插件目录一起安装。字体准备步骤会将十款静态字体复制到 `resources/fonts/kindlespouse`，进入标准字体目录。

## 验证与目前限制

工作流生成字体和主页安装包，并下载指纹固定的官方 x86_64 KOReader v2026.07.1，在隔离环境验证搜索、阅读状态／作者／格式／文件夹筛选、收藏、书集、排序、网格和列表、十款字体加载、双标签、原生标题栏、横竖屏与设置恢复。可在产物中查看运行时截图。

本地执行同一验收：

```sh
python3 kindlespouse/test_home.py --runtime /path/to/koreader
```

当前版本补齐了书架的基础筛选与管理入口。第一代 Scribe 上的触控、手写切换、休眠唤醒及大量图书时的性能仍需真机验证。当前包不替代 Kindle 的原生手写编辑器，不承诺与 KindleSpouse 桌面应用或 Apple Books 完全相同的外观和全部功能。

用户要求原有 Scribe 笔记继续编辑，因此没有用独立手写插件替换原始笔记。[Notebook 插件的存储实现](https://github.com/pierspad/notebook.koplugin/blob/fb66d7cfbf57ef67183795530f9bec014abdaffc/lua/documentstorage.lua)保存自己的页面／笔画结构；[Ink Away](https://github.com/EmirErtorer/ink-away.koplugin/tree/0c4a45a613a96cfb6ae87d8356695f93af71687f)也使用自己的笔记库并支持 PDF／图片导入。当前没有实现可验证的 Amazon 原生笔记格式回写。原有笔记仍需使用 Kindle 系统编辑，这项完整融合要求尚未完成。

上游版权及 AGPLv3 保留。字体分别采用 SIL OFL、带字体嵌入例外的 GPL 或 IPA Font License 1.0，原始许可和 Fandol 上游归档随包分发。字体文件保持原样；霞鹜新致宋的 IPA 许可与其固定版本信息一并提供。
