/// tomgen's `build_runner` entry point, re-exported under the package's own
/// name. `build.yaml` references [tomgBuilder] directly as
/// `package:tomgen/builder.dart`; this file exists so `import
/// 'package:tomgen/tomgen.dart';` also works, by convention.
library;

export 'builder.dart';
export 'src/cli/app.dart' show TomgenApp;
export 'src/cli/config.dart';
export 'src/cli/emitter.dart';
export 'src/cli/errors.dart';
export 'src/cli/generator.dart';
export 'src/cli/ownership.dart';
export 'src/cli/project.dart';
export 'src/cli/schema.dart';
export 'src/registry_document.dart';
