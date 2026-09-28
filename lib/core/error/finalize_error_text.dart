/// 终稿（filetrans）失败原因的**用户可读文案映射**。
///
/// 设计约定：数据库 `meetings.finalize_error` 保留**原始错误**（error.toString()，
/// 便于日志诊断与问题定位）；本函数只在**展示层**把原始错误翻译成用户能懂的话。
/// 映射按「特征子串」匹配，顺序即优先级（最具体的在前）；全部未命中走兜底文案。
library;

/// 终稿失败的用户可读文案。
///
/// - [raw]：数据库里存的原始错误串（error.toString()），可为 null；
/// - 返回值保证**不暴露堆栈 / 错误码 / 英文异常名**，且适合直接拼进提示条。
String friendlyFinalizeError(String? raw) {
  final String s = (raw ?? '').trim();
  if (s.isEmpty) return '转写失败，请重试';

  // 1) 无有效语音（模拟器空录 / 全程静音的已知形态）。
  if (s.contains('HAVE_NO_WORDS') || s.contains('无有效语音')) {
    return '录音里没有识别到说话内容，可能全程静音或音量过低';
  }
  // 2) 文件超限。
  if (s.contains('E_TOO_LARGE') || s.contains('文件过大') || s.contains('超过上限')) {
    return '录音文件过大，暂时无法上传转写';
  }
  // 3) 任务超时。
  if (s.contains('E_TIMEOUT') ||
      s.contains('TimeoutException') ||
      s.contains('超时')) {
    return '转写服务响应超时，请重试';
  }
  // 4) 鉴权失败（Key 无效 / 过期）。
  if (s.contains('401') ||
      s.contains('InvalidApiKey') ||
      s.contains('Unauthorized') ||
      s.contains('AuthenticationError') ||
      s.contains('API Key') ||
      s.contains('apikey')) {
    return '服务鉴权失败，请检查 API Key 配置';
  }
  // 5) 网络异常。
  if (s.contains('SocketException') ||
      s.contains('Connection') ||
      s.contains('Failed host lookup') ||
      s.contains('E_NETWORK')) {
    return '网络连接异常，请检查网络后重试';
  }
  // 6) 限流 / 服务繁忙。
  if (s.contains('Throttling') || s.contains('429') || s.contains('限流')) {
    return '转写服务繁忙，请稍后重试';
  }
  // 7) 上传 / 提交 / 轮询链路协议类错误。
  if (s.contains('上传凭证') ||
      s.contains('E_PROTOCOL') ||
      s.contains('提交 filetrans 失败')) {
    return '转写服务连接异常，请稍后重试';
  }
  // 8) 任务最终失败（含 filetrans 侧状态非 succeeded 的其余情况）。
  if (s.contains('E_TASK_FAILED') ||
      s.contains('filetrans 未成功') ||
      s.contains('TaskStatus')) {
    return '转写服务处理失败，请重试';
  }
  // 9) 本地数据 / 归档问题。
  if (s.contains('会议不存在') || s.contains('归档')) {
    return '录音文件缺失，无法重试';
  }
  // 兜底：未知错误——给出可行动的指引，不暴露原始串。
  return '转写失败，请重试；多次失败请检查网络或稍后再试';
}
