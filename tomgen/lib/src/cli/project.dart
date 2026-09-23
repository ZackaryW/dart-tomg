import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'errors.dart';

final RegExp _packageNamePattern = RegExp(r'^[a-z][a-z0-9_]*$');

/// A Dart package selected by walking upward from the CLI working directory.
final class TomgenProject {
  const TomgenProject({required this.root, required this.packageName});

  final Directory root;
  final String packageName;

  static TomgenProject discover(Directory start) {
    var directory = start.absolute;
    while (true) {
      final pubspec = File(p.join(directory.path, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        final canonicalRoot = Directory(directory.resolveSymbolicLinksSync());
        return TomgenProject(
          root: canonicalRoot,
          packageName: _readPackageName(
            File(p.join(canonicalRoot.path, 'pubspec.yaml')),
          ),
        );
      }
      final parent = directory.parent;
      if (p.equals(parent.path, directory.path)) {
        throw TomgenException(
          'No pubspec.yaml was found at or above "${start.path}".',
        );
      }
      directory = parent;
    }
  }

  static String _readPackageName(File pubspec) {
    final Object? document;
    try {
      document = loadYaml(pubspec.readAsStringSync());
    } on Object catch (error) {
      throw TomgenException('Failed to parse ${pubspec.path}: $error');
    }
    if (document is! YamlMap) {
      throw TomgenException('${pubspec.path} must contain a YAML map.');
    }
    final name = document['name'];
    if (name is! String || !_packageNamePattern.hasMatch(name)) {
      throw TomgenException(
        '${pubspec.path} must declare a valid Dart package name.',
      );
    }
    return name;
  }
}

/// Resolves [relativePath] within [root] and rejects lexical or symlink escape.
String resolveContainedPath({
  required Directory root,
  required String relativePath,
  required String description,
  bool mustExist = false,
  bool requireDescendant = false,
}) {
  if (p.isAbsolute(relativePath)) {
    throw TomgenException('$description must be package-relative.');
  }

  final rootPath = root.resolveSymbolicLinksSync();
  final lexical = p.normalize(p.join(rootPath, relativePath));
  if ((!p.equals(rootPath, lexical) && !p.isWithin(rootPath, lexical)) ||
      (requireDescendant && !p.isWithin(rootPath, lexical))) {
    throw TomgenException('$description escapes ${root.path}.');
  }

  final resolved = _resolveThroughExistingAncestor(lexical);
  if ((!p.equals(rootPath, resolved) && !p.isWithin(rootPath, resolved)) ||
      (requireDescendant && !p.isWithin(rootPath, resolved))) {
    throw TomgenException('$description escapes ${root.path} through a link.');
  }
  if (mustExist &&
      FileSystemEntity.typeSync(resolved) == FileSystemEntityType.notFound) {
    throw TomgenException('$description does not exist: $relativePath');
  }
  return resolved;
}

String _resolveThroughExistingAncestor(String path) {
  var cursor = path;
  final suffix = <String>[];
  while (FileSystemEntity.typeSync(cursor, followLinks: false) ==
      FileSystemEntityType.notFound) {
    final parent = p.dirname(cursor);
    if (p.equals(parent, cursor)) break;
    suffix.insert(0, p.basename(cursor));
    cursor = parent;
  }

  final resolvedAncestor =
      FileSystemEntity.typeSync(cursor) == FileSystemEntityType.notFound
      ? p.normalize(cursor)
      : File(cursor).resolveSymbolicLinksSync();
  return p.normalize(p.joinAll(<String>[resolvedAncestor, ...suffix]));
}
