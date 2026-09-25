/// 首页「一句话」Provider：调一言（hitokoto.cn）公开 API 取一句短句。
///
/// - `autoDispose`：每次进入首页重新请求一次；
/// - 网络失败 / 超时 → 返回 null（首页静默隐藏该行，不弹错误）；
/// - 句子类型 `c=i`（诗词）+ `c=k`（文学），最长 28 字，保证一行放得下。
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 一言 API 端点。
const String kHitokotoEndpoint = 'https://v1.hitokoto.cn';

/// 每次进入首页取一句「一句话」；失败返回 null。
final FutureProvider<String?> dailyQuoteProvider =
    FutureProvider<String?>((Ref ref) async {
  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(milliseconds: 4000),
      receiveTimeout: const Duration(milliseconds: 4000),
    ),
  );
  try {
    final Response<Map<String, dynamic>> response =
        await dio.get<Map<String, dynamic>>(
      kHitokotoEndpoint,
      queryParameters: <String, dynamic>{
        'c': 'i', // 诗词
        'max_length': 28, // 保证一行放得下
      },
    );
    final Map<String, dynamic>? data = response.data;
    if (data == null) return null;
    final String? sentence = data['hitokoto'] as String?;
    final String? from = data['from'] as String?;
    if (sentence == null || sentence.isEmpty) return null;
    return from == null || from.isEmpty ? sentence : '$sentence —— $from';
  } catch (_) {
    // 无网 / 超时：静默隐藏。
    return null;
  }
});
