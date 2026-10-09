/// 版本更新检查逻辑单测。
///
/// 覆盖纯函数 [needsUpdate]、[RemoteVersion.fromJson]，以及 [AppUpdateChecker.check]
/// 的成功 / 失败路径。通过注入 `fetch` 与 `localVersionCodeProvider` 避免触碰
/// `PackageInfo.fromPlatform`（测试环境无平台通道）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:smart_minutes_flutter/core/update/app_update.dart';

void main() {
  group('needsUpdate', () {
    const RemoteVersion valid = RemoteVersion(
      version: '1.0.1',
      versionCode: 2,
      downloadUrl: 'https://example.com/a.apk',
    );

    test('远端版本更高 → 需要更新', () {
      expect(needsUpdate(1, valid), isTrue);
    });

    test('本地已是最新或更高 → 不需要更新', () {
      expect(needsUpdate(2, valid), isFalse);
      expect(needsUpdate(3, valid), isFalse);
    });

    test('manifest 无效（versionCode<=0 或无下载地址）→ 不更新', () {
      const RemoteVersion bad = RemoteVersion(version: '', versionCode: 0, downloadUrl: '');
      const RemoteVersion noUrl = RemoteVersion(version: '1.0.1', versionCode: 2, downloadUrl: '');
      expect(needsUpdate(1, bad), isFalse);
      expect(needsUpdate(1, noUrl), isFalse);
    });

    test('远端 minVersionCode 高于本地 → 需要更新（即便版本号相等）', () {
      const RemoteVersion forced = RemoteVersion(
        version: '1.0.1',
        versionCode: 2,
        downloadUrl: 'https://example.com/a.apk',
        minVersionCode: 2,
      );
      expect(needsUpdate(1, forced), isTrue);
      // 本地已满足最低要求时不强制。
      expect(needsUpdate(2, forced), isFalse);
    });
  });

  group('RemoteVersion.fromJson', () {
    test('字段缺失给安全默认', () {
      final RemoteVersion r = RemoteVersion.fromJson(<String, dynamic>{});
      expect(r.version, '');
      expect(r.versionCode, 0);
      expect(r.downloadUrl, '');
      expect(r.forceUpdate, isFalse);
      expect(r.minVersionCode, 0);
    });

    test('正常解析含全部字段', () {
      final RemoteVersion r = RemoteVersion.fromJson(<String, dynamic>{
        'version': '1.0.1',
        'versionCode': 2,
        'downloadUrl': 'https://x/a.apk',
        'buildStamp': '1009/abc',
        'releaseNotes': '说明',
        'forceUpdate': true,
        'minVersionCode': 2,
      });
      expect(r.version, '1.0.1');
      expect(r.versionCode, 2);
      expect(r.downloadUrl, 'https://x/a.apk');
      expect(r.buildStamp, '1009/abc');
      expect(r.releaseNotes, '说明');
      expect(r.forceUpdate, isTrue);
      expect(r.minVersionCode, 2);
    });
  });

  group('AppUpdateChecker.check', () {
    test('manifest 更高 → available=true', () async {
      final AppUpdateChecker checker = AppUpdateChecker(
        manifestUrl: 'https://x/version.json',
        fetch: (_) async => <String, dynamic>{
          'version': '1.0.1',
          'versionCode': 2,
          'downloadUrl': 'https://x/a.apk',
        },
        localVersionCodeProvider: () async => 1,
      );
      final UpdateDecision d = await checker.check();
      expect(d.available, isTrue);
      expect(d.remote?.version, '1.0.1');
    });

    test('manifest 不可达 → available=false 且不抛', () async {
      final AppUpdateChecker checker = AppUpdateChecker(
        manifestUrl: 'https://x/version.json',
        fetch: (_) => Future<Map<String, dynamic>>.error('network'),
        localVersionCodeProvider: () async => 1,
      );
      final UpdateDecision d = await checker.check();
      expect(d.available, isFalse);
    });

    test('manifest 字段无效 → available=false', () async {
      final AppUpdateChecker checker = AppUpdateChecker(
        manifestUrl: 'https://x/version.json',
        fetch: (_) async => <String, dynamic>{'foo': 'bar'},
        localVersionCodeProvider: () async => 1,
      );
      final UpdateDecision d = await checker.check();
      expect(d.available, isFalse);
    });
  });

  group('AppUpdateChecker.checkStrict（手动检查：失败抛出）', () {
    test('manifest 更高 → available=true', () async {
      final AppUpdateChecker checker = AppUpdateChecker(
        manifestUrl: 'https://x/version.json',
        fetch: (_) async => <String, dynamic>{
          'version': '1.0.3',
          'versionCode': 4,
          'downloadUrl': 'https://x/a.apk',
        },
        localVersionCodeProvider: () async => 3,
      );
      final UpdateDecision d = await checker.checkStrict();
      expect(d.available, isTrue);
      expect(d.remote?.version, '1.0.3');
    });

    test('本地已是最新 → available=false（不抛）', () async {
      final AppUpdateChecker checker = AppUpdateChecker(
        manifestUrl: 'https://x/version.json',
        fetch: (_) async => <String, dynamic>{
          'version': '1.0.3',
          'versionCode': 4,
          'downloadUrl': 'https://x/a.apk',
        },
        localVersionCodeProvider: () async => 4,
      );
      final UpdateDecision d = await checker.checkStrict();
      expect(d.available, isFalse);
    });

    test('manifest 不可达 → 抛出（与 check 的静默语义区分）', () async {
      final AppUpdateChecker checker = AppUpdateChecker(
        manifestUrl: 'https://x/version.json',
        fetch: (_) => Future<Map<String, dynamic>>.error(StateError('network')),
        localVersionCodeProvider: () async => 1,
      );
      await expectLater(checker.checkStrict(), throwsA(isA<StateError>()));
    });
  });
}
