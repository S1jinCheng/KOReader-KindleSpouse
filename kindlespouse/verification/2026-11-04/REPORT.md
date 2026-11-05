# v2026.07.1 运行时验收报告

本报告对应 `codex/improvement-12-notebook`，不包含 PR #13 的精简实现。结果、日志和截图来自本次重新执行，未复用此前的运行。

## 本次执行

- 日期：2026-11-04，Asia/Shanghai。
- 开始：`2026-11-04T22:05:36.369748+08:00`。
- 结束：`2026-11-04T22:10:58.591393+08:00`。
- 被测提交：`7a8fe56ec8909c226ff2e618e803627f15b79e2f`。后续归档提交只增加本目录的验收证据。
- 环境：Windows 上的 WSL Ubuntu，官方 v2026.07.1 AppImage 的本地解压运行时，真实 LuaJIT、KOReader UIManager 和 dummy SDL 显示。
- 实际规范化版本：`202607010000`，版本探针通过。原始输出见 [version.log](runtime-checks/suite-x6zsrpif/version.log)。
- LuaJIT SHA-256：`d45e2e20df501f0aabc2eb55c5e6138090d48bae423d4de87ac3df113e8eee3c`。
- 本次重建的叠加包 SHA-256：`4d09c838d5b6ec944d17b3716a8b34d76e427e13ddbbfa86b109790273cb37ce`。解压安装包的测试使用同一份包。
- 数据：仅测试脚本生成的书籍、笔记、sidecar 和模拟进程状态；未连接真实网盘、未访问设备、未使用个人书库或授权。

执行命令：

```sh
/usr/bin/python3 kindlespouse/test_runtime.py --runtime /mnt/d/kindleBooming/KindleSpouse/native/tools/koreader/squashfs-root/usr/lib/koreader --fonts /mnt/d/kindleBooming/KindleSpouse/native/tools/reader-fonts --package /mnt/d/kindleBooming/koreader-kindlespouse/kindlespouse/build/KindleSpouse-Scribe-Overlay.zip --expected-version 202607010000
```

## 完整测试组结果

24 组全部 PASS，失败 0 组，跳过 0 组；runner 退出码为 0。原始 [result.json](runtime-checks/suite-x6zsrpif/result.json) 包含实际执行顺序及每组退出码。

- `annotation`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/annotation.log)。 [runtime.log 末尾 50 行](groups/annotation/)，共 1 份日志、0 张截图。
- `patches`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/patches.log)。 [runtime.log 末尾 50 行](groups/patches/)，共 1 份日志、0 张截图。
- `scheduler`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/scheduler.log)。 [runtime.log 末尾 50 行](groups/scheduler/)，共 1 份日志、0 张截图。
- `launcher`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/launcher.log)。 [runtime.log 末尾 50 行](groups/launcher/)，共 1 份日志、0 张截图。
- `scheduler_integration`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/scheduler_integration.log)。 [runtime.log 末尾 50 行](groups/scheduler_integration/)，共 1 份日志、0 张截图。
- `main_lifecycle`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/main_lifecycle.log)。 [runtime.log 末尾 50 行](groups/main_lifecycle/)，共 1 份日志、0 张截图。
- `services-UTC`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/services-UTC.log)。 [runtime.log 末尾 50 行](groups/services-UTC/)，共 1 份日志、0 张截图。
- `services-Asia-Shanghai`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/services-Asia-Shanghai.log)。 [runtime.log 末尾 50 行](groups/services-Asia-Shanghai/)，共 1 份日志、0 张截图。
- `services-America-New_York`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/services-America-New_York.log)。 [runtime.log 末尾 50 行](groups/services-America-New_York/)，共 1 份日志、0 张截图。
- `localization`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/localization.log)。 该检查器只输出 stdout，不创建独立 runtime.log，也不生成截图；完整原始输出已保留。
- `version-guard`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/version-guard.log)。 [runtime.log 末尾 50 行](groups/version-guard/)，共 1 份日志、0 张截图。
- `home-guard`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/home-guard.log)。 [runtime.log 末尾 50 行](groups/home-guard/)，共 10 份日志、9 张截图。
- `catalog-500`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/catalog-500.log)。 [runtime.log 末尾 50 行](groups/catalog-500/)，共 1 份日志、0 张截图。
- `notebook`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/notebook.log)。 [runtime.log 末尾 50 行](groups/notebook/)，共 1 份日志、1 张截图。
- `home`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/home.log)。 [runtime.log 末尾 50 行](groups/home/)，共 1 份日志、6 张截图。
- `home-en`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/home-en.log)。 [runtime.log 末尾 50 行](groups/home-en/)，共 1 份日志、6 张截图。
- `home-zh_CN`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/home-zh_CN.log)。 [runtime.log 末尾 50 行](groups/home-zh_CN/)，共 1 份日志、6 张截图。
- `home-500`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/home-500.log)。 [runtime.log 末尾 50 行](groups/home-500/)，共 1 份日志、1 张截图。
- `highlight`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/highlight.log)。 [runtime.log 末尾 50 行](groups/highlight/)，共 1 份日志、6 张截图。
- `reader-monochrome`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/reader-monochrome.log)。 [runtime.log 末尾 50 行](groups/reader-monochrome/)，共 1 份日志、8 张截图。
- `package-reader-monochrome`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/package-reader-monochrome.log)。 [runtime.log 末尾 50 行](groups/package-reader-monochrome/)，共 1 份日志、8 张截图。
- `reader-color`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/reader-color.log)。 [runtime.log 末尾 50 行](groups/reader-color/)，共 1 份日志、20 张截图。
- `package-reader-color`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/package-reader-color.log)。 [runtime.log 末尾 50 行](groups/package-reader-color/)，共 1 份日志、20 张截图。
- `package-home`：PASS，exit=0。[完整组输出](runtime-checks/suite-x6zsrpif/package-home.log)。 [runtime.log 末尾 50 行](groups/package-home/)，共 1 份日志、6 张截图。

## 修复提交与对应验收

### 1. 阅读中每十分钟同步脏阅读记录

提交：[`ac538f90`](https://github.com/S1jinCheng/KOReader-KindleSpouse/commit/ac538f90f99c064aae1b0ce22697d7ace448a8be)。

测试组：`scheduler`、`scheduler_integration`、`launcher`。

PASS。scheduler 的 25 个场景包含 599/600 秒边界、上传期间产生新一代脏数据、失败退避、暂停、断网及恢复；集成组核对多 host、工作进程与结果身份。时间边界使用可控时钟，不代表本次进行了十分钟真机阅读。

### 2. 已完成 root 在进程启动后增量重扫一次

提交：[`c68c8581`](https://github.com/S1jinCheng/KOReader-KindleSpouse/commit/c68c85810d70121352b09c36f40fe05547bc4e39)。

测试组：`catalog-500`、`home-500`。

PASS。500 本书验收覆盖 fresh-module 重启后的新增、修改、移除及并发 ensure 共用扫描；比较大小和修改时间。书库热操作及实际 ReaderUI 返回路径的书籍目录遍历断言为 0。冷扫、显式增量扫和启动重扫各 51 次，共 153 次目录访问。

### 3. 首次 setupLayout 已构建 Home 时不再次 reinit

提交：[`16eea04f`](https://github.com/S1jinCheng/KOReader-KindleSpouse/commit/16eea04f8e53dd407a49c37ca900865751c084c6)。

测试组：`home`、`home-en`、`home-zh_CN`、`home-500`、`home-guard`、`package-home`。

PASS。启动布局及实际打开书籍后返回书架均断言新 FileManager 的 Home.layout 为 1 次；故障回退仍生效。集成组还覆盖 20 次标签往返及清理。

### 4. 版本验收入口及 v2026.07.2 白名单

提交：[`7a8fe56e`](https://github.com/S1jinCheng/KOReader-KindleSpouse/commit/7a8fe56ec8909c226ff2e618e803627f15b79e2f)。

测试组：`version-guard`、`main_lifecycle`、`home-guard`。

v2026.07.1 的版本守卫、生命周期与完整 24 组运行时验收 PASS。v2026.07.2 支持未完成：没有取得该精确版本的官方 AppImage，只有标签源码资源，因此没有启用 v2026.07.2 白名单。模拟不支持版本的回退通过，不能算作 v2026.07.2 的真实运行时验收。README 已区分已验证和待验证版本。

### 5. 单色屏高亮按钮与用户 drawer

提交：[`eb3a243a`](https://github.com/S1jinCheng/KOReader-KindleSpouse/commit/eb3a243a4c188705ab9d3cf3e741a075bcab11e7)。

测试组：`highlight`、`reader-monochrome`、`reader-color`、`package-reader-monochrome`、`package-reader-color`。

PASS。单色屏只提供一个原生 Highlight 按钮，保存的 drawer、当前选择的 drawer 和默认样式均保留；彩色屏保留颜色选择。检查真实上游保存路径、旧回调、More、生命周期和从安装包加载后的行为。彩色屏能力在模拟器中设置，未使用彩色真机。

### 6. Notebook 跳过 new 记录并使用 DocSettings 查找

提交：[`4c20bba8`](https://github.com/S1jinCheng/KOReader-KindleSpouse/commit/4c20bba898c986a4b0c03b3a3412c4288d518b2c)。

测试组：`notebook`、`home-en`、`home-zh_CN`、`package-home`。

PASS。status 为 new 的记录不执行 sidecar 查找、stat 或读取；DocSettings.findSidecarFile 的目录偏好得到验证。读取有大小上限并保留损坏文件，主批注集合与打开中的内存批注保持权威。索引不调用会迁移或删除损坏文件的完整 DocSettings:open，也不自行重建上游 MRU 恢复规则。

### 7. Launcher 与 scheduler 用户可见错误本地化

提交：[`e7463c29`](https://github.com/S1jinCheng/KOReader-KindleSpouse/commit/e7463c290b27e117e667fdd649575f4c297235be)。

测试组：`localization`、`launcher`、`scheduler`、`scheduler_integration`、`services-UTC`、`services-Asia-Shanghai`、`services-America-New_York`。

PASS。52 项启动器可见失败覆盖中英文；scheduler 故障提示通过翻译键输出。原始诊断保留在带 KindleSpouse 前缀的日志中。i18n 检查器扫描 launcher 和 scheduler；状态解析在三个时区通过。

## 未通过、跳过与证据范围

- 本次 test_runtime.py 的 24 个组没有失败或跳过。原始日志中的 synthetic failure、warning 和 traceback 可能来自故障注入；组退出码和验收断言决定该组是否通过。
- v2026.07.2 的精确 AppImage 验收未执行，原因是缺少该产物；它不属于这次 v2026.07.1 的 24 组。白名单没有扩大。
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

- `runtime-checks/suite-x6zsrpif/` 保存原样复制的结果 JSON、版本探针输出和全部 24 组 stdout/stderr 文件。
- `groups/` 保存 32 份 runtime.log 的原始末尾 50 行和 97 张本次生成的截图。home-guard 包含十个子场景，因此日志数多于组数；其中 supported 子场景不调用截图，其余九个子场景各生成一张，没有遗漏输出。日志不足 50 行时保留全部内容。
- [MANIFEST.json](MANIFEST.json) 记录每个文件的来源、复制方式、原文件与归档文件 SHA-256、字节数和测试组目录。
- 日志尾部由原始字节按行截取，未解码重写；JSON 和 PNG 按字节复制，未重排字段、改写数值、重编码或缩放。目录内 `.gitattributes` 禁用证据文件的自动换行转换。
- 归档仅包含此次运行创建或更新的输出。没有提交生成的书籍、原始笔记、资料目录、字体缓存、配对文件或网盘授权。
