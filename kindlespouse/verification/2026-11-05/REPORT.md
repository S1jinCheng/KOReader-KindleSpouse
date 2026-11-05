# v2026.07.1 运行时验收报告

本报告对应 `codex/improvement-12-notebook` 的本轮三项修复，不包含 PR #13 的精简实现。上一轮证据保留在 2026-11-04 目录。结果、日志和截图来自本次重新执行，未复用此前的运行。

## 本次执行

- 日期：2026-11-05，Asia/Shanghai。
- 开始：`2026-11-05T18:20:53.376619+08:00`。
- 结束：`2026-11-05T18:27:21.097855+08:00`。
- 被测提交：`99f438572d9d55261c90bec4b7ad58b8d393a56f`。后续归档提交只增加本目录的验收证据。完整运行入口已加入 cached-startup 和 reader-pdf 测试组。
- 环境：Windows 上的 WSL Ubuntu，官方 v2026.07.1 AppImage 的本地解压运行时，真实 LuaJIT、KOReader UIManager 和 dummy SDL 显示。
- 实际规范化版本：`202607010000`，版本探针通过。原始输出见 [version.log](runtime-checks/suite-hajl1uxq/version.log)。
- LuaJIT SHA-256：`d45e2e20df501f0aabc2eb55c5e6138090d48bae423d4de87ac3df113e8eee3c`。
- 本次重建的叠加包 SHA-256：`8dca5376a20d0861b9cf727facb2014507387d857c43bf7576530e7738322658`。解压安装包的测试使用同一份包。
- 数据：仅测试脚本生成的书籍、笔记、sidecar 和模拟进程状态；未连接真实网盘、未访问设备、未使用个人书库或授权。

执行命令：

```sh
/usr/bin/python3 kindlespouse/test_runtime.py --runtime /mnt/d/kindleBooming/KindleSpouse/native/tools/koreader/squashfs-root/usr/lib/koreader --fonts /mnt/d/kindleBooming/KindleSpouse/native/tools/reader-fonts --package /mnt/d/kindleBooming/koreader-kindlespouse/kindlespouse/build/KindleSpouse-Scribe-Overlay.zip --expected-version 202607010000
```

## 新截图

- [缓存扫描进行中，书单仍为 120 本](groups/cached-startup/cached-startup-checks/run-oq7xl0gu/cached-startup-in-progress.png)
- [阅读工具栏与完整正文，中文](groups/reader-monochrome/reader-checks/all-drt3t_1m/reader-body-unobscured-zh.png)
- [PDF 阅读工具栏与完整页面](groups/reader-pdf/reader-checks/reader-l48gsqqx/reader-body-unobscured.png)
- [Notebook 中文详情与三层排版](groups/home-zh_CN/artifacts/integrated-zh_CN/koreader-home-notebook-detail.png)

完整应用截图优先看 home-zh_CN 或 package-home。独立 notebook 夹具把面板嵌入屏幕减去 150px 的区域，底部可见原阅读器，这是夹具布局；完整应用截图没有这段背景。

## 完整测试组结果

最终完整重跑的 26 组全部 PASS，失败 0 组，跳过 0 组；runner 退出码为 0。首次尝试的失败单独保留，见后文。原始 [result.json](runtime-checks/suite-hajl1uxq/result.json) 包含实际执行顺序及每组退出码。

- `annotation`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/annotation.log)。 [runtime.log 末尾 50 行](groups/annotation/)，共 1 份日志、0 张截图。
- `patches`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/patches.log)。 [runtime.log 末尾 50 行](groups/patches/)，共 1 份日志、0 张截图。
- `scheduler`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/scheduler.log)。 [runtime.log 末尾 50 行](groups/scheduler/)，共 1 份日志、0 张截图。
- `launcher`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/launcher.log)。 [runtime.log 末尾 50 行](groups/launcher/)，共 1 份日志、0 张截图。
- `scheduler_integration`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/scheduler_integration.log)。 [runtime.log 末尾 50 行](groups/scheduler_integration/)，共 1 份日志、0 张截图。
- `main_lifecycle`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/main_lifecycle.log)。 [runtime.log 末尾 50 行](groups/main_lifecycle/)，共 1 份日志、0 张截图。
- `services-UTC`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/services-UTC.log)。 [runtime.log 末尾 50 行](groups/services-UTC/)，共 1 份日志、0 张截图。
- `services-Asia-Shanghai`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/services-Asia-Shanghai.log)。 [runtime.log 末尾 50 行](groups/services-Asia-Shanghai/)，共 1 份日志、0 张截图。
- `services-America-New_York`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/services-America-New_York.log)。 [runtime.log 末尾 50 行](groups/services-America-New_York/)，共 1 份日志、0 张截图。
- `localization`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/localization.log)。 该检查器只输出 stdout，不创建独立 runtime.log，也不生成截图；完整原始输出已保留。
- `version-guard`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/version-guard.log)。 [runtime.log 末尾 50 行](groups/version-guard/)，共 1 份日志、0 张截图。
- `home-guard`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/home-guard.log)。 [runtime.log 末尾 50 行](groups/home-guard/)，共 10 份日志、9 张截图。
- `catalog-500`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/catalog-500.log)。 [runtime.log 末尾 50 行](groups/catalog-500/)，共 1 份日志、0 张截图。
- `cached-startup`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/cached-startup.log)。 [runtime.log 末尾 50 行](groups/cached-startup/)，共 2 份日志、1 张截图。
- `notebook`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/notebook.log)。 [runtime.log 末尾 50 行](groups/notebook/)，共 1 份日志、3 张截图。
- `home`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/home.log)。 [runtime.log 末尾 50 行](groups/home/)，共 1 份日志、6 张截图。
- `home-en`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/home-en.log)。 [runtime.log 末尾 50 行](groups/home-en/)，共 1 份日志、6 张截图。
- `home-zh_CN`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/home-zh_CN.log)。 [runtime.log 末尾 50 行](groups/home-zh_CN/)，共 1 份日志、6 张截图。
- `home-500`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/home-500.log)。 [runtime.log 末尾 50 行](groups/home-500/)，共 1 份日志、1 张截图。
- `highlight`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/highlight.log)。 [runtime.log 末尾 50 行](groups/highlight/)，共 1 份日志、6 张截图。
- `reader-monochrome`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/reader-monochrome.log)。 [runtime.log 末尾 50 行](groups/reader-monochrome/)，共 1 份日志、16 张截图。
- `package-reader-monochrome`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/package-reader-monochrome.log)。 [runtime.log 末尾 50 行](groups/package-reader-monochrome/)，共 1 份日志、16 张截图。
- `reader-color`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/reader-color.log)。 [runtime.log 末尾 50 行](groups/reader-color/)，共 1 份日志、28 张截图。
- `package-reader-color`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/package-reader-color.log)。 [runtime.log 末尾 50 行](groups/package-reader-color/)，共 1 份日志、28 张截图。
- `reader-pdf`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/reader-pdf.log)。 [runtime.log 末尾 50 行](groups/reader-pdf/)，共 1 份日志、10 张截图。
- `package-home`：PASS，exit=0。[完整组输出](runtime-checks/suite-hajl1uxq/package-home.log)。 [runtime.log 末尾 50 行](groups/package-home/)，共 1 份日志、6 张截图。

## 修复提交与对应验收

### 1. 已完成书库的静默启动扫描

提交：[`1928f027`](https://github.com/S1jinCheng/KOReader-KindleSpouse/commit/1928f0279faa5667cf5c16016726940cebb586dc)。

测试组：`cached-startup`、`catalog-500`、`home`、`home-500`、`home-guard`。

PASS。新测试用两个独立进程预热和重启缓存；在后台扫描仍未完成、已经发现外部新增书时截图。书架、FileChooser 和 catalog 仍显示原来的 120 本，没有扫描事件或“正在整理书库”提示。取消并重新打开仍保留完整缓存且继续静默扫描；完成后更新为 121 本，热操作目录扫描为 0。冷启动和手动刷新仍保留原扫描反馈。

### 2. 阅读工具栏分隔线、完整正文与剩余时间

提交：[`1ff32697`](https://github.com/S1jinCheng/KOReader-KindleSpouse/commit/1ff32697cade949f0949da996cc40e13ffafb6d1)。

测试组：`reader-monochrome`、`reader-color`、`package-reader-monochrome`、`package-reader-color`、`reader-pdf`。

PASS。顶栏下方和底栏上方各绘制 1 个物理像素的分隔线；工具栏显示时把完整原页临时等比例放入正文区域，关闭后恢复原比例，分页和阅读位置不改写。剩余时间使用统计的数值时长生成“约 X 分钟”或“约 X 小时 Y 分”，不解析本地化时间字符串。仅移除标题末尾多余的“· 阅读”。实际像素、文本和生命周期断言见对应日志。

### 3. Notebook 书名与三层批注排版

提交：[`e6ccb89e`](https://github.com/S1jinCheng/KOReader-KindleSpouse/commit/e6ccb89ee605473dd10bc84d7a837d12a35faf71)。

测试组：`notebook`、`home-en`、`home-zh_CN`、`package-home`。

PASS。详情标题使用 catalog 的书名；每条分别排版高亮原文、带“笔记：”前缀的缩进笔记，以及小号灰色章节和日期，并绘制条目分隔线。真实运行时检查书名与文件名不同、文字换行、分页和点击定位；原有搜索、缓存、主批注集合及标签往返验收保留。

目录异常与取消保护的补充提交：[`e8f8ab64`](https://github.com/S1jinCheng/KOReader-KindleSpouse/commit/e8f8ab64e4b09c3b86d4dcd48f9eef83b65a9541)。目录打开或迭代失败不发布不完整结果，保留缓存且不会自动忙重试。

完整测试入口与 CI 补充提交：`2c09f98c7008558a0b953e2e030473c3b45c1ddf`；catalog 回调变量命名修复：`3fc62b8b5356e3d825ab87814bd08fc57a465c1c`。

## 未通过、跳过与证据范围

- 最终这次 test_runtime.py 的 26 个组没有失败或跳过。原始日志中的 synthetic failure、warning 和 traceback 可能来自故障注入；组退出码和验收断言决定该组是否通过。
- 首次尝试 suite-6om04qw5 在 services-UTC 失败：服务契约测试还调用已被新分钟/小时文案替换的 reader.remaining 键。6 组已通过，1 组失败，19 组因 runner 遇错停止而未执行。[原始失败结果](failed-attempt-01/runtime-checks/suite-6om04qw5/result.json) 和 [日志](failed-attempt-01/runtime-checks/suite-6om04qw5/services-UTC.log) 均保留。修复提交 `99f438572d9d55261c90bec4b7ad58b8d393a56f` 把对应断言迁移为中英文分钟与小时各两项校验，没有删除状态、结果身份或生命周期测试。
- 首次归档器遇到尚未创建的缓存测试目录而停止；已有输出未修改，随后按原始字节补收该次实际执行的七份 runtime.log 尾部，见 failed-attempt-01/MANIFEST.json。最终归档器已兼容提前停止。
- v2026.07.2 的精确 AppImage 验收未执行，原因是缺少该产物；它不属于这次 v2026.07.1 的 26 组。白名单没有扩大。
- 真实 600 秒空闲测试不在 test_runtime.py 中，本次没有额外执行；已有的旧 scheduler-idle.json 不属于本次归档证据。scheduler 的 600 秒边界在可控时钟测试中通过。
- 没有进行真实云端传输、Scribe 触控或电量测量。模拟器通过不等于这些项目已验证。

## 仍未在真机验证的项目

- Scribe 上 200 本以上的冷启动、首次后台扫描、外部拷入文件后重启入库，以及筛选、排序时的输入响应和电子墨水刷新。
- 真机实际关闭书籍返回书架时只构建一次 Home；横竖屏切换、休眠和唤醒后仍保持目录与滚动位置。
- 连续阅读时每十分钟的脏数据同步，上传期间继续阅读，Wi-Fi 恢复、暂停、退避及省电表现。真实网盘速度、自动收书及时性和端到端回执未验证。
- 手指和笔的选择坐标、单色屏各 drawer 样式、More 和原生键盘交互。彩色设备上的颜色显示也未做真机验证。
- 真实设备 sidecar 目录设置、批注改动后的索引失效、EPUB xpointer 定位及 PDF 页码和几何位置；原生手写入口正常保存退出并返回 Kindle 系统。
- 在设备上关闭定制主页、阅读工具栏或笔记页后恢复上游行为，以及版本不支持时界面回退和同步独立初始化。

Amazon 原生 NBK 手写编辑未实现，不能列作已支持或只待测试的功能。本次没有连接 USB 或安装更新。

## 原始证据与完整性

- `runtime-checks/suite-hajl1uxq/` 保存原样复制的结果 JSON、版本探针输出和全部 26 组 stdout/stderr 文件。
- `groups/` 保存 35 份 runtime.log 的原始末尾 50 行和 142 张本次生成的截图及像素比对图。home-guard 包含十个子场景，cached-startup 包含预热与重启两个进程，因此日志数多于组数；日志不足 50 行时保留全部内容。
- [MANIFEST.json](MANIFEST.json) 记录每个文件的来源、复制方式、原文件与归档文件 SHA-256、字节数和测试组目录。
- 日志尾部由原始字节按行截取，未解码重写；JSON 和 PNG 按字节复制，未重排字段、改写数值、重编码或缩放。目录内 `.gitattributes` 禁用证据文件的自动换行转换。
- 归档仅包含此次运行创建或更新的输出。没有提交生成的书籍、原始笔记、资料目录、字体缓存、配对文件或网盘授权。
