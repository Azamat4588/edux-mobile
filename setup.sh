#!/usr/bin/env bash
# EduX mobil ilovasini birinchi marta tayyorlash (macOS yoki Linux; Windows — README dagi buyruqlar).
#   bash setup.sh
# Talab: Flutter 3.24+ (flutter doctor toza), Android uchun Android Studio + NDK, iOS uchun Xcode + CocoaPods.
set -euo pipefail
cd "$(dirname "$0")"

command -v flutter >/dev/null || { echo "Flutter topilmadi: https://docs.flutter.dev/get-started/install"; exit 1; }

# Android va iOS papkalari (mavjud fayllar o'zgarmaydi)
flutter create --org uz.edux --project-name edux --platforms=android,ios .
# flutter create namuna testini qo'shadi — u bu ilovaga tegishli emas
if [ -f test/widget_test.dart ] && grep -q "MyApp" test/widget_test.dart; then rm test/widget_test.dart; fi

flutter pub get
dart run tool/configure_platforms.dart
dart run flutter_launcher_icons

echo
echo "Tayyor. Ishga tushirish:  flutter run --dart-define=EDUX_SERVER=https://app.sizning-domen.uz"
echo "Android APK:            flutter build apk --release --dart-define=EDUX_SERVER=https://app.sizning-domen.uz"
echo "iOS (Xcode orqali):     flutter build ipa --release --dart-define=EDUX_SERVER=https://app.sizning-domen.uz"
