import 'package:edux/core/notification_store.dart';
import 'package:edux/features/callcenter/callcenter_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppNotification _item(String id, {bool read = false}) => AppNotification(
      id: id,
      title: "To'lov qabul qilindi",
      body: '100 000',
      data: <String, dynamic>{'type': 'payment', 'student_id': '7'},
      receivedAt: DateTime(2026, 10, 19, 12),
      read: read,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('bildirishnomalar: takrorlanmaydi, o\'qilgan belgisi va soni', () async {
    final store = NotificationStore.instance;
    await store.clear();
    await store.add(_item('a'));
    await store.add(_item('b'));
    // Fonda yozilgan xabar bosilganda yana keladi — takrorlanmasin, o'qilgan bo'lsin
    await store.add(_item('a', read: true));
    expect(store.items.length, 2);
    expect(store.unread, 1);
    expect(store.items.first.id, 'b');
    expect(store.items.first.type, 'payment');

    await store.markAllRead();
    expect(store.unread, 0);
    await store.remove('a');
    expect(store.items.map((item) => item.id), <String>['b']);
  });

  test('bildirishnomalar: eng ko\'pi 100 ta saqlanadi', () async {
    final store = NotificationStore.instance;
    await store.clear();
    for (var i = 0; i < NotificationStore.limit + 5; i++) {
      await NotificationStore.persist(_item('n$i'));
    }
    await store.load();
    expect(store.items.length, NotificationStore.limit);
    expect(store.items.first.id, 'n${NotificationStore.limit + 4}');
  });

  test('call markazi: raqam va davomiylik', () {
    expect(dialable('+998 (90) 123-45-67'), '+998901234567');
    expect(callDuration(75), '1:15');
    expect(callDuration(null), '—');
  });
}
