import 'package:edux/features/access/face_checkin_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Face ID sahifasi manzili', () {
    expect(faceCheckinPath(), '/attendance/camera?mode=face&embed=1');
    expect(faceCheckinPath(groupId: 42), '/attendance/camera?mode=face&embed=1&group_id=42');
  });

  test('«Kamerani yopish» manzili ushlanadi', () {
    expect(isCameraDoneUrl('https://edux.uz/attendance/camera/done'), isTrue);
    expect(isCameraDoneUrl('https://edux.uz/attendance/camera/done/'), isTrue);
    expect(isCameraDoneUrl('https://edux.uz/attendance/camera?mode=face'), isFalse);
    expect(isCameraDoneUrl('https://edux.uz/attendance'), isFalse);
  });
}
