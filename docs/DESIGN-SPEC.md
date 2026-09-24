# 设计规格（DESIGN-SPEC）—— Flutter 移动端 UI 还原依据

> 来源：ardot 设计稿《智能会议纪要 · 移动端 UI 设计》
> 文件：`https://ardot.tencent.com/file/729192876417296`（13 个页面 + StatusBar / TabBar / HistoryCard 组件）
> 视觉参考图已导出：`docs/design-reference/*.png`（01-idle / 02-recording / 04-history / 07-transcript / 11-minutes-long）
> 本文档由主理人从画布逐节点读取后汇编，色值与字号均为**画布实测**，非估算。

---

## 一、设计语言总览

**暖奶油纸感 + 橙色主色**。与 Web 端（Zinc 冷灰 + teal）是两套语言，**不要**把 Web 的 token 带进来。

- 底色是暖奶油（近纸色），卡片纯白、大圆角、暖棕柔和阴影
- 主色橙只用于：录音按钮、选中态、主要 CTA、链接与强调文字、说话人 1
- 文字是暖棕系（不是黑/灰），次级文字是暖灰褐
- 说话人用多彩圆点区分（橙 / 绿 / 紫…）

## 二、设计 Tokens（画布实测值）

### 2.1 颜色

| Token | 值 | 用途 |
|---|---|---|
| `bg` | `#FAF3EC` | 页面背景（rgb 0.980/0.953/0.925） |
| `surface` | `#FFFFFF` | 卡片、TabBar Pill、分段控件选中项 |
| `hairline` | `#F2E4D6` | 卡片描边 / 分隔线（rgb 0.949/0.894/0.839） |
| `primary` | `#F0783C` | 主橙：录音按钮、CTA、选中态（rgb 0.941/0.471/0.235） |
| `primarySoft` | `#FFF0E3` | 主橙浅底：光晕、徽标底、分段 track 选中底（rgb 1/0.941/0.890） |
| `primaryDeep` | `#C2591F` | 深橙文字：徽标文字、链接（rgb 0.761/0.349/0.122） |
| `trackSoft` | `#FBF3EC` | 分段控件轨道底（rgb 0.984/0.953/0.925） |
| `ink` | `#3A2A20` | 主文字（暖深棕，rgb 0.227/0.165/0.125） |
| `ink2` | `#8B7565` | 次级文字 / 元信息（暖灰褐，rgb 0.545/0.459/0.396） |
| `dot` | `#C9BBAE` | 装饰圆点 / 占位头像（rgb 0.788/0.733/0.682） |

说话人色板（圆点 + 序号徽标）：说话人1 = 主橙 `#F0783C`、说话人2 = 绿、说话人3 = 紫，其余按序扩展；
历史卡片占位头像点用 `#C4B3A4`。

### 2.2 圆角

| 元素 | 值 |
|---|---|
| Hero 卡（待机态录音卡） | 28 |
| 转写卡 / 纪要卡 / 信息卡 | 22 |
| 历史卡片 | 18 |
| 麦克风主按钮 | 64（正圆） |
| 光晕（mic 外圈） | 84 |
| TabBar Pill | 36 |
| 分段控件：轨道 21 / 选中项 17 | — |
| 徽标 badge | 8 |
| Toast | 见 2:546 |

### 2.3 阴影（暖棕，非灰黑）

`#9E8066`（rgb 0.62/0.50/0.40）+ alpha：
- Hero 卡：alpha 0.14，offset y=10，blur 30，spread −6
- 转写卡 / 纪要卡：alpha 0.12，offset y=8，blur 24，spread −6
- TabBar Pill：alpha 0.18，offset y=6，blur 18，spread −2

### 2.4 字体与字号（Noto Sans SC）

| 字号 | 字重 | 用途 |
|---|---|---|
| 48± | Bold | 录音计时器 `12:34` |
| 22± | Bold | 页面大标题「开始记录」 |
| 17 | SemiBold | 卡片主文案「点击开始录音」 |
| 14 | SemiBold | 卡片标题（历史条目、会议名） |
| 13 | SemiBold / Medium | 分段控件、片段正文 |
| 12 | Regular | 元信息、状态行、说话人标签 |
| 11 | Regular | 次级元信息 |
| 10 | SemiBold | 徽标（已总结 / 已完成 / 内容较长） |

### 2.5 间距

- 页面左右边距：**20**
- 卡片内边距：16–22
- 内容区块纵向节奏：16–22
- TabBar：左右 21、上 12、下 21（含安全区），Pill 高 62

## 三、屏幕清单与布局（13 屏）

| # | 画布节点 | 名称 | 要点 |
|---|---|---|---|
| 01 | `2:32` | 主页面 · 待机态 | 问候语 + 大标题「开始记录」+ 右上头像；Hero 卡（状态行「待机中 · 今日已记录 N 分钟」+ 大橙圆 mic + 「点击开始录音」+ 模式分段 会议/访谈/灵感）；最近记录 2 卡 + 查看全部 |
| 02 | `2:90` | 主页面 · 录音中 | TopBar（✕ / 录音中·会议模式 / ⚙）；红点 + 大号计时；波形条（橙色深浅）；说话人 chips；转写卡（自动滚动 chip + 序号徽标片段）；ActionRow（暂停 / 结束并生成 / 书签） |
| 03 | `2:224` | 主页面 · 纪要生成 | 生成中态 |
| 04 | `2:286` | 历史记录 | Header + 搜索框（radius 21，高 42）+ 过滤 chips + 历史列表 |
| 05 | `2:398` | 我的 | 设置页 |
| 06 | `2:556` | 录音中 · 断线重连 | 录音态的断线提示变体 |
| 07 | `2:698` | 完整转写 | TopBar + InfoBar（radius 14）+ 说话人过滤 chips + 转写列表 + CtaRow |
| 08 | `2:784` | 历史 · 空态 | 空态 |
| 09 | `2:840` | 历史 · 超长列表 | 长列表 |
| 10 | `2:899` | 历史 · 搜索无结果 | 搜索空态 |
| 11 | `2:949` | 纪要 · 总结超长 | TopBar（✕ / 会议纪要·生成于 / 分享）；会议信息卡；AI 结构化纪要卡（模型 chip + 内容较长 chip + 摘要折叠「展开全文 · 摘要约 N 字」+ 重要决策·共 N 条 + 查看全部 N 条 + 讨论要点 + 查看完整转写 N 字）；底部「导出纪要」CTA + 书签 FAB |
| 12 | `2:1025` | 转写 · 超长内容 | 长转写 |
| 13 | `2:1123` | 录音中 · 说话人过多 | 多说话人变体 |

### 关键交互（对应此前用户痛点）

- **开始录音位置**：待机态是**居中大圆 mic 按钮**（点击开始录音），录音态 ActionRow 是「暂停 / 结束并生成 / 书签」三键，底部 TabBar 常驻
- **纪要超长**：摘要**默认折叠**，`展开全文 · 摘要约 N 字` 展开；结构化分节（重要决策 / 讨论要点）各自 `查看全部 N 条`；`查看完整转写` 是**独立入口行**——不靠长滚动
- **转写超长**：说话人过滤 chips + 自动滚动

## 四、组件清单

`StatusBar`（2:1，组件）、`TabBar`（2:14，组件：Tab-Record / Tab-History / Tab-Me，选中态为橙色 pill）、
`RecordHeroCard`（2:41）、`TranscriptCard`（2:160）、`HistoryCard`（2:311，组件：标题 + 三个占位头像点 + 元信息 + 徽标）、
`MeetingInfoCard`（2:953）、`AISummaryCard`（2:954）、`SpeakerChips`（2:150）、`Waveform`（2:107）、
`ActionRow`（2:195）、`CtaRow`（2:764 / 2:955）、`Toast-断线重连`（2:546）、`SearchBar`（2:296）、`FilterChips`（2:301）。

## 五、与现有 Flutter 结构的映射

新项目 `smart-minutes-flutter/`，T01–T04 已完成（`lib/core`、`lib/backend`、`lib/domain`），UI 层落在：

```
lib/ui/
  theme/app_theme.dart        ← 第二节全部 token（ColorScheme + ThemeData + 自定义 AppColors）
  router/app_router.dart      ← 路由（T01 已建空壳）
  shell/app_shell.dart        ← 底部 TabBar + 页面切换
  pages/home_page.dart        ← 01/02/03/06/13（待机 / 录音 / 生成 / 重连 / 多说话人 同页不同态）
  pages/history_page.dart     ← 04/08/09/10
  pages/meeting_page.dart     ← 07/11/12（完整转写 / 纪要）
  pages/profile_page.dart     ← 05
  widgets/                    ← RecordHeroCard / TranscriptCard / HistoryCard / AISummaryCard /
                                SpeakerChips / Waveform / ActionRow / CtaRow / AppBadge / AppToast
```

TabBar 三项：录音（`/`）、历史（`/history`）、我的（`/profile`）——与设计稿一致，无知识库。

## 六、硬约束

- 字体 **Noto Sans SC**（pubspec 引 `google_fonts` 或随包 asset；WebView 离线包体可接受，按架构文档 §2.4 结论执行）
- 触控目标 ≥ 44；文字 ≥ 10（设计最小 10，仅徽标）
- 底部固定元素计入 TabBar 高（95）与安全区
- 不引入组件库（沿用既有零依赖约定）；图标用内联 SVG 或 Material symbols 替代画布中的 emoji/图形
- 语义色对比度：`#8B7565` 在 `#FAF3EC` 上约 3.9:1，仅用于 ≥12px 次级文字；正文一律 `#3A2A20`
