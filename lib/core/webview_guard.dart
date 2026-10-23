// WebView xavfsizligi: ilova tokeni WebView xotirasida (localStorage) qolib ketmasin; ruxsat rad etilganda —
// telefon sozlamalaridagi ilova sahifasini ochish.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// WebView localStorage va cookie'larini tozalaydi (chiqishda va lab sahifasi yopilganda). Xato bo'lsa — jim.
Future<void> clearWebViewData() async {
  if (!(Platform.isAndroid || Platform.isIOS)) return;
  try {
    await WebViewController().clearLocalStorage();
    await WebViewCookieManager().clearCookies();
  } catch (_) {
    // WebView hali yaratilmagan yoki platforma qo'llamaydi — saqlangan narsa yo'q
  }
}

/// Telefon sozlamalarida EduX ilovasi sahifasi (kamera, SMS ruxsatlari). Ochilmasa — false.
Future<bool> openAppSettings() async {
  try {
    if (Platform.isIOS) return await launchUrl(Uri.parse('app-settings:'));
    if (Platform.isAndroid) return await const MethodChannel('edux/sms').invokeMethod<bool>('openAppSettings') ?? false;
  } catch (_) {}
  return false;
}
