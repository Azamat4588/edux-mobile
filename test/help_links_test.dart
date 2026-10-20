import 'package:edux/core/help_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('yordam markazi manzillari', () {
    expect(HelpLinks.url('https://app.edux.uz/').toString(), 'https://app.edux.uz/help?lang=uz');
    expect(HelpLinks.url('https://app.edux.uz', HelpLinks.scanner).toString(), 'https://app.edux.uz/yordam/varaqani-skanerlash?lang=uz');
    expect(HelpLinks.url('http://192.168.1.5:8000', 'farzandim').toString(), 'http://192.168.1.5:8000/yordam/farzandim?lang=uz');
  });
}
