# 内置 Notebook：仅电脑模拟

本分支在同一个 KOReader 进程内接入手写编辑器。Notebook 封面页沿用主页顶部设置及 Library／Notebook 底部导航，提供搜索、新建、文件夹和排序。点击笔记封面后直接书写，保存后返回笔记封面。

模拟引擎为 [pierspad/notebook.koplugin](https://github.com/pierspad/notebook.koplugin)，MIT，固定提交及压缩包 SHA-256 见 `engine.json`。引擎的完整上游源代码与 MIT 许可证下载到本机测试目录，实验适配器使用 AGPL-3.0。

运行 `python3 experiments/notebook/simulate.py --runtime /absolute/path/to/koreader`，在真实 KOReader v2026.07.1 运行时中检查封面点击、搜索、触摸输入、橡皮、撤销重做、页面切换、文件夹、保存重开、返回 Library 和横竖屏。所有公开截图与自动验证均使用合成笔记，不连接 Kindle。

这个实验没有加入正式安装包，不修改 KOReader 启动器，也不安装到设备。

旧 Scribe 笔记可以由 KindleSpouse 主项目的离线解码工具读取为向量，再由 `import.lua` 导入独立 `.scribe` 文件。一次本地私人备份验证包含 5 页、1547 条笔画，旧笔画删除、撤销、续写与保存重开通过，原始 NBK 哈希保持不变；原始文件及其内容不发布。公开测试只使用合成向量样本。

**尚不能将修改写回 Amazon NBK 并继续由原生编辑器编辑。** 当前是可编辑副本，笔刷、颜色和透明度有近似映射，原生模板和云同步语义没有恢复。模拟器也无法证明真机笔延迟、压感或手掌抑制体验。因此本分支是电脑研究结果，不应视为原生 Scribe 笔记兼容已经完成。
