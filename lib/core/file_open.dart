// Serverdan yuklangan faylni (baytlar) telefonning vaqtinchalik papkasiga yozib, tizim ilovasida ochish.
// Kurs materiallari va suhbat ilovalari shu yo'l bilan ochiladi.
import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Faylni ochadi; ochadigan ilova topilmasa `false`.
Future<bool> openBytesAsFile(List<int> bytes, String fileName, {String prefix = ''}) async {
  final dir = await getTemporaryDirectory();
  final safe = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  final file = File('${dir.path}/$prefix${safe.isEmpty ? 'fayl' : safe}');
  await file.writeAsBytes(bytes, flush: true);
  final result = await OpenFilex.open(file.path);
  return result.type == ResultType.done;
}
