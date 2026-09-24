/// 录音模式（设计稿 01 号屏的分段控件：会议 / 访谈 / 灵感）。
///
/// 仅用于**会议标题前缀**与界面展示，不影响后端链路：
/// 三条链路（实时 ASR / 终稿 filetrans / LLM 纪要）对三种模式完全一致。
library;

/// 录音模式。
enum RecordingMode {
  /// 会议。
  meeting('会议', '会议'),

  /// 访谈。
  interview('访谈', '访谈'),

  /// 灵感。
  inspiration('灵感', '灵感');

  /// 构造模式。
  const RecordingMode(this.label, this.titlePrefix);

  /// 界面文案。
  final String label;

  /// 自动会议标题前缀。
  final String titlePrefix;
}
