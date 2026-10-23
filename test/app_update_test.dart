// 3.6.0: ilova ichida yangilanish tekshiruvi (GET public/apps → mobile.android.version).
import 'package:edux/core/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('versiyalarni solishtirish', () {
    expect(compareVersions('3.6.0', '3.5.0'), greaterThan(0));
    expect(compareVersions('3.10.0', '3.9.9'), greaterThan(0));
    expect(compareVersions('3.6.0+11', '3.6.0'), 0);
    expect(compareVersions('v3.6', '3.6.0'), 0);
    expect(compareVersions('3.5.9', '3.6.0'), lessThan(0));
    expect(compareVersions('4.0.0-beta', '3.9.0'), greaterThan(0));
  });

  Map<String, dynamic> apps(String? version, {String? play, String apk = 'https://edux.uz/download/android'}) => <String, dynamic>{
        'mobile': <String, dynamic>{
          'android': <String, dynamic>{'apk_url': apk, 'play_url': play, 'version': version},
          'ios': <String, dynamic>{'app_store_url': null},
        },
      };

  test('yangilanish: faqat server versiyasi yangiroq bo\'lsa', () {
    expect(updateFrom(apps(null), platform: 'android', current: '3.6.0'), isNull);
    expect(updateFrom(apps('3.6.0'), platform: 'android', current: '3.6.0'), isNull);
    expect(updateFrom(apps('3.5.0'), platform: 'android', current: '3.6.0'), isNull);
    final info = updateFrom(apps('3.7.0'), platform: 'android', current: '3.6.0')!;
    expect(info.version, '3.7.0');
    expect(info.url, 'https://edux.uz/download/android');
    expect(info.store, isFalse);
    final play = updateFrom(apps('3.7.0', play: 'https://play.google.com/store/apps/details?id=uz.edux.edux'), platform: 'android', current: '3.6.0')!;
    expect(play.store, isTrue);
    expect(play.url, contains('play.google.com'));
    expect(updateFrom(apps('3.7.0', apk: 'http://x'), platform: 'android', current: '3.6.0'), isNull, reason: 'faqat https');
    expect(updateFrom(apps('9.0.0'), platform: 'ios', current: '3.6.0'), isNull);
  });

  test('eski server: platforms.android', () {
    final info = updateFrom(<String, dynamic>{
      'platforms': <String, dynamic>{'android': <String, dynamic>{'apk_url': 'https://a/b.apk', 'version': '3.8.0'}},
    }, platform: 'android', current: '3.6.0');
    expect(info?.version, '3.8.0');
  });
}
