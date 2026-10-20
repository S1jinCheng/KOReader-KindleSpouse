# KOReader 内置 Notebook 电脑实验

本次新版仅在电脑运行并提供预览。用户看过布局、完成修改后，再安排 USB 安装；原生编辑器跳转测试仍暂停。

Notebook 标签页在同一个 KOReader 进程中显示笔记封面，保留主页顶部设置和 Library／Notebook 两个底部标签。搜索、新建笔记、文件夹与排序集中在一行。点击封面进入手写编辑器，保存返回后继续显示笔记封面；不经过 Kindle 首页或 KUAL。

手写引擎采用 [pierspad/notebook.koplugin](https://github.com/pierspad/notebook.koplugin)，MIT，固定提交和完整源代码压缩包 SHA-256 记录在 `engine.json`。引擎及其许可证保存在忽略跟踪的本机测试目录；没有修改或重发上游源代码。实验适配器和 KOReader 主页共同使用 AGPL-3.0，见 `LICENSE`。

## 当前验证

已在真实 KOReader v2026.07.1 的 SDL 模拟器中验证封面点按、笔记搜索、触摸输入画笔、整笔橡皮、撤销／重做按钮、多页切换、文件夹进入／返回、保存重开和两个底部标签切换，并检查竖屏、横屏截图。所有截图使用合成笔记。

新版 Library 和 Notebook 共用纵向滚动书架，封面下显示名称，移除页码与翻页按钮，缩小顶部、工具栏和底部标签的字号与间距。测试覆盖滑动距离、不误触封面、滑动后长按选择、标签切换后的滚动位置恢复，以及 1000 项书架的可见区域渲染。搜索、阅读状态、收藏、书集、作者／格式／目录筛选、排序和列表切换继续通过验收，十种中文字体通过常用汉字字形检查。启动枚举只读取已有元数据，不再为整个书库同步打开文档；这项改动不能单独证明此前设备停留在 Opening 的具体原因。

另用电脑端已有的一个私人 Scribe 笔记备份进行离线解码：5 页、1547 条原始笔画。向量导入后可以删除旧笔画、撤销，再添加新笔画并保存重开；原始 NBK 文件 SHA-256 保持不变。私人文件和其截图不发布。

**这仍未满足“直接编辑原来的 Amazon 原生笔记文件”的完整要求。** 编辑结果保存在独立 `.scribe` 副本中，尚不能写回 Amazon NBK 并交由原生编辑器继续编辑。导入不是 PDF 叠写，旧笔画确实作为独立对象载入，但笔刷、颜色、透明度等仍存在近似映射；原生纸张模板、云端标识和同步语义没有恢复。模拟器也不能证明真机笔延迟、压感和手掌抑制效果。

## 在 KindleSpouse 主项目复现

准备项目现有 KOReader 运行时后，运行 `npm run test:notebook-embedded`。测试自行生成书籍与笔记样本，结果位于 `artifacts/notebook-embedded-*.png`，运行数据仅位于 `.test-data`。

已有解码器通过 `scripts/install-notebook-tool.mjs` 准备。`decode.mjs` 是独立的 GPL-3.0-only 离线入口，使用已有 `neo_scribe_to_pdf` 解码模块，只读取本地 NBK 副本并写入一个全新的向量 JSON 文件，不能写回 NBK。其许可证见 `DECODE-LICENSE`。启用私人备份测试需要本地提供 `.test-data/notebook-offline/latest-path.txt`；公开自动测试不会读取用户目录。

## 在 KOReader fork 或 Linux 复现

运行 `python3 experiments/notebook/simulate.py --runtime /absolute/path/to/koreader`。脚本只下载并校验固定版本手写引擎，在独立测试目录中运行 KOReader，并生成合成数据截图。也可通过 `--engine /absolute/path/to/notebook/lua` 使用已有引擎。

KOReader fork 中实验不会进入正式安装包，不会修改启动器。NBK 离线解码工具仍位于 KindleSpouse 主项目，fork 的公开自动验证仅使用合成向量样本。

## 用户授权的设备预览

先退出 KOReader 并连接 USB。依次运行 `scripts/prepare-notebook-preview.ps1`、`node scripts/build-notebook-preview.mjs`、`node scripts/verify-notebook-preview.mjs`，最后运行 `scripts/install-notebook-preview.ps1`。这些步骤会读取设备上的独立原生笔记，生成单独的 `.scribe` 副本，并用与设备安装相同的补丁、插件和引擎文件在模拟器中检查启动、列表、书写、保存重开与返回主页。

安装器要求 KOReader v2026.07.1，备份将被覆盖的组件及阅读设置，逐文件回读校验，最后才安装激活补丁。副本放在 `koreader/notebook/Scribe 可编辑副本`，首次进入 Notebook 会显示该目录。已有同名副本目录时停止，防止覆盖用户对副本的修改。原生 `.notebooks` 目录没有写入目标，安装结束后重新读取原生笔记并核对哈希；配对配置及已有阅读设置不由安装器改写。

上一版用户授权的安装准备了 28 本副本、158 页、44382 条原始笔画，安装后 219 个文件回读校验通过，28 份原生笔记哈希保持不变。设备启动和实际书写体验仍需用户试用确认；成功复制与校验不代表已经完成真机笔体验验收。

输入快照、解码向量、私人副本、文件清单、备份及运行记录均只存放在忽略跟踪的 `.test-data/notebook-preview-*`。这些目录包含私人内容，不能上传 GitHub 或作为公开安装包分发。
