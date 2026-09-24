/// 百炼端点解析（移植 `dashscopeClient.js:89-124`）。
///
/// Workspace 专属域名优先，未配置 WorkspaceId 时回退公共域名。
library;

import '../../../core/config/app_config.dart';

/// 解析后的端点集合。
class BailianEndpoints {
  /// 构造端点集合。
  const BailianEndpoints({
    required this.wsUrl,
    required this.httpBase,
    required this.region,
    required this.usingWorkspaceDomain,
  });

  /// 实时 WS URL。
  final String wsUrl;

  /// HTTP base（无尾斜杠）。
  final String httpBase;

  /// 地域。
  final String region;

  /// 是否使用 Workspace 专属域名。
  final bool usingWorkspaceDomain;
}

/// 解析百炼端点。
BailianEndpoints resolveEndpoints(AppConfig cfg) {
  final String region = cfg.bailianRegion.isEmpty ? 'cn-beijing' : cfg.bailianRegion;
  final String regionHost = region.contains('aliyuncs.com') ? region : '$region.maas.aliyuncs.com';
  final String workspaceId = cfg.dashscopeWorkspaceId;
  final bool usingWorkspaceDomain = workspaceId.isNotEmpty;
  final String defaultWs = usingWorkspaceDomain
      ? 'wss://$workspaceId.$regionHost/api-ws/v1/inference'
      : 'wss://dashscope.aliyuncs.com/api-ws/v1/inference';
  final String defaultHttp = usingWorkspaceDomain
      ? 'https://$workspaceId.$regionHost'
      : 'https://dashscope.aliyuncs.com';
  return BailianEndpoints(
    wsUrl: cfg.realtimeWsUrl.isNotEmpty ? cfg.realtimeWsUrl : defaultWs,
    httpBase: _trimTrailingSlash(cfg.bailianHttpBase.isNotEmpty ? cfg.bailianHttpBase : defaultHttp),
    region: region,
    usingWorkspaceDomain: usingWorkspaceDomain,
  );
}

/// 组装实时 WS URL（优先 `cfg.realtimeWsUrl`）。
String buildWsUrl(AppConfig cfg) => resolveEndpoints(cfg).wsUrl;

/// 组装 HTTP base（优先 `cfg.bailianHttpBase`；无尾斜杠）。
String buildHttpBase(AppConfig cfg) => resolveEndpoints(cfg).httpBase;

/// 去掉尾部斜杠。
String _trimTrailingSlash(String value) => value.replaceAll(RegExp(r'/+$'), '');
