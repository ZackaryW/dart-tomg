import 'dart:io';

import 'package:tomgen/tomgen.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await TomgenApp().run(arguments);
}
