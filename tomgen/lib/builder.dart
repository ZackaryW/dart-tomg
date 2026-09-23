import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/tomg_generator.dart';

/// Builder factory referenced by `build.yaml`. Wraps [TomgGenerator] in a
/// [SharedPartBuilder] so its output is combined into the annotated
/// library's single `.g.dart` part alongside any other part-builders.
Builder tomgBuilder(BuilderOptions options) =>
    SharedPartBuilder([TomgGenerator()], 'tomg');
