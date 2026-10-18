/// 运行模式标记：**无界面（headless）还是已挂 UI**。
///
/// 背景：本 app 支持「长按智能键 → 息屏静默录音」，这条路径下进程被拉起时
/// **没有任何 FlutterView**。此时标准的 `runApp()` 会抛 `StateError`
/// （没有 view 可挂），因此原生侧改走 `headlessMain()` 入口：只装配
/// ProviderContainer，不执行 `runApp`。
///
/// 这个文件用两个进程级标志区分三种情形：
/// 1. 正常冷启动（用户点图标）→ [isHeadlessMode]=false, [isUiAttached]=true；
/// 2. 按键触发冷启动 → [isHeadlessMode]=true, [isUiAttached]=false；
/// 3. 按键触发后用户又打开了 app → [isHeadlessMode]=true, [isUiAttached]=true
///    （Dart isolate 已存在，只能补挂 UI，不能重跑入口）。
///
/// 哪些代码需要关心：
/// - 任何会弹权限对话框 / 依赖 Activity 的调用（headless 下没有 Activity，
///   调用会抛 `ActivityNotAttachedException`）；
/// - 麦克风权限查询（`record` 插件在 activity==null 时直接返回 false）。
library;

bool _headless = false;
bool _uiAttached = false;

/// 当前是否为无界面模式（进程由按键触发拉起）。
bool get isHeadlessMode => _headless;

/// UI 是否已附着（`runApp` 已执行、有可见界面）。
bool get isUiAttached => _uiAttached;

/// 标记为无界面模式（[headlessMain] 启动时调用一次）。
void markHeadlessMode() {
  _headless = true;
}

/// 标记 UI 已附着（[main] 或补挂 UI 成功后调用）。
void markUiAttached() {
  _uiAttached = true;
}
