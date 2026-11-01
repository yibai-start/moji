# 墨记 moji

一款纯本地、无服务端的鸿蒙原生笔记 + 待办应用。没有账号、不联网、不上传，所有数据只存在你自己的设备上。

- **笔记**：记想法、贴图片、用彩色标签归类，写得随手，找得回来。
- **待办**：带截止时间和优先级，到期会提醒你，桌面卡片每天看一眼。
- **本地**：数据放在设备关系型数据库里，可随时导出成一份 JSON 备份带走。

适用设备：phone / tablet / 2in1，宽屏下自动切换成双栏布局。

## 功能

### 笔记
- 标题 + 正文，编辑过程中自动保存，退出即落库
- 多标签归类，标签有语义颜色（红=紧急、蓝=工作、绿=生活…可自定义）
- 按标签筛选，标题与正文全文搜索
- 置顶：点卡片右上角图钉，或**卡片右滑**直接置顶 / 取消置顶
- 本地图片：从系统相册选图，图片复制进应用沙箱 `files/images`；缩略图可单张删除，点击任意图片进入全屏预览，多图支持左右滑动翻页
- 删除笔记时一并清理它引用的图片文件

### 待办
- 标题 + 详情，截止时间、三档优先级（低 / 中 / 高）
- 勾选完成、逾期标记，按「全部 / 进行中 / 今天 / 已完成」过滤
- 今日进度条与未完成计数
- 到期提醒：基于 Agent Reminder；「我的」页可一键开启通知权限，未授权时提醒不会展示

### 标签
- 自定义名称与颜色，标签名唯一（重名会提示创建失败）
- 标签页显示每个标签被引用的次数（`N 处使用`）

### 桌面服务卡片
- 「今日待办」卡片（2×4），无需打开应用即可查看当天要做的事
- 由 FormKit 渲染，待办数据变化时应用会主动推送刷新；点击卡片直接打开应用

### 数据与外观
- 深色模式跟随系统
- 导出备份：把标签 / 笔记 / 待办写成一个 JSON 文件（`mojian-backup-*.json`）
- 从备份恢复：选择墨记导出的 JSON 文件覆盖恢复，非本应用格式会被拒绝
- 系统备份恢复通道（BackupExtension）

## 技术栈

| 项 | 说明 |
| --- | --- |
| 系统 | HarmonyOS 6.1.0(API 23)，Stage 模型 |
| 语言 / UI | ArkTS + ArkUI 声明式（`@Component` / `@Builder` / `bindSheet`） |
| 存储 | `@kit.ArkData` relationalStore（SQLite），5 张表：`tag` `note` `todo` `note_tag` `todo_tag` |
| 图片 | `@kit.CoreFileKit` fileIo + `photoAccessHelper.PhotoViewPicker` 选图，落沙箱目录 |
| 提醒 | `@kit.BackgroundTasksKit` agentReminder（需 `ohos.permission.PUBLISH_AGENT_REMINDER`） |
| 卡片 | FormKit + `EntryFormAbility` / `TodoFormAbility` |
| 宽屏 | `matchMediaSync` 断点判定，双栏 / 单栏自适应 |
| 依赖 | 无第三方运行时依赖，仅 devDependencies 里的 hypium / hamock 用于测试 |

## 目录结构

```
AppScope/                       应用级配置与图标
entry/src/main/ets/
  common/                       常量与工具函数
  components/                   NoteCard / NoteEditor / TagChip / TodoRow
  data/                         Database、NoteDao / TodoDao / TagDao、SeedService
  pages/Index.ets               主页面（笔记 / 待办 / 标签 / 我的 四个 Tab）
  service/                      ImageService、ReminderService、BackupService、WidgetService
  widget/pages/TodoWidget.ets   服务卡片 UI
  entryability/                 UIAbility 入口
  entryformability/             卡片 Ability
  entrybackupability/           系统备份扩展
entry/src/main/resources/       文案、颜色（含 dark 限定）、图标、卡片配置
```

## 构建与运行

环境：DevEco Studio 6.x + HarmonyOS SDK 6.1.0(23)。真机和模拟器都能跑，但相册选图流程只在真机可用（见「已知边界」）。

1. 克隆仓库后用 DevEco Studio 打开项目根目录。
2. **配置签名**：仓库出于安全考虑不包含签名材料（`build-profile.json5` 的 `signingConfigs` 为空）。
   打开 `File > Project Structure > Signing Configs`，登录华为账号并勾选 `Automatically sign`，
   IDE 会生成本地调试证书。未配置签名时只能产出 unsigned HAP，无法安装到真机。
3. 运行：在 DevEco Studio 里直接点 Run 最简单。命令行打包用 DevEco 自带的 hvigor（仓库未包含 `hvigorw` 包装脚本）：

```bash
# 在 DevEco Studio 的 Terminal 中，或用 IDE 内置的 hvigor 入口
hvigorw --mode module -p product=default assembleHap --no-daemon
# 产物：entry/build/default/outputs/default/entry-default-signed.hap
```

4. 安装到已连接的设备：

```bash
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

首次启动会写入一批示例数据（欢迎笔记、几条待办和标签），方便直接体验；删掉它们即可从零开始。

## 已知边界

- 图片只存在本机沙箱，**不包含在 JSON 备份里**；换设备时图片需要另行迁移。
- 模拟器的系统相册选图流程无法完成，图片相关功能建议在真机验证。
- 提醒依赖系统通知权限，未授权时提醒不会展示。

## 说明

交互与功能灵感来自开源项目 [Notesnook](https://github.com/streetwriters/notesnook)（GPL-3.0）。墨记是对它的一次原生 ArkTS 重写，不含其任何源码，数据全部留在本机。

本项目暂未附加开源许可证。
