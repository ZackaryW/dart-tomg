import 'dart:io';

import 'package:path/path.dart' as p;

final class TestPackage {
  TestPackage._(this.root);

  final Directory root;

  static TestPackage create({String name = 'test_package'}) {
    final root = Directory.systemTemp.createTempSync('tomgen_test_');
    Directory(p.join(root.path, 'lib')).createSync();
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: $name
environment:
  sdk: ^3.12.2
''');
    return TestPackage._(root);
  }

  File write(String relative, String content) {
    final file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  void dispose() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}
