import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'errors.dart';

final RegExp _packageNamePattern = RegExp(r'^[a-z][a-z0-9_]*$');

/// A Dart package selected by walking upward from the CLI working directory.
final class TomgenProject {
  const TomgenProject({
    required this.root,
    required this.packageName,
    required this.sourceBoundary,
  });

  final Directory root;
  final String packageName;
  final Directory sourceBoundary;

  bool get hasWorkspaceBoundary => !p.equals(root.path, sourceBoundary.path);

  static TomgenProject discover(Directory start) {
    var directory = start.absolute;
    while (true) {
      final pubspec = File(p.join(directory.path, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        final canonicalRoot = Directory(directory.resolveSymbolicLinksSync());
        return TomgenProject(
          root: canonicalRoot,
          packageName: readPubPackageName(
            File(p.join(canonicalRoot.path, 'pubspec.yaml')),
          ),
          sourceBoundary: discoverSourceBoundary(canonicalRoot),
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
}

String readPubPackageName(File pubspec) {
  final document = _readPubspec(pubspec);
  final name = document['name'];
  if (name is! String || !_packageNamePattern.hasMatch(name)) {
    throw TomgenException(
      '${pubspec.path} must declare a valid Dart package name.',
    );
  }
  return name;
}

/// Returns the nearest ancestor pub workspace that contains [packageRoot].
/// Falls back to [packageRoot] for a standalone package.
Directory discoverSourceBoundary(Directory packageRoot) {
  final canonicalPackage = Directory(packageRoot.resolveSymbolicLinksSync());
  var directory = canonicalPackage.parent;
  while (true) {
    final pubspec = File(p.join(directory.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      final workspace = _readPubspec(pubspec)['workspace'];
      if (workspace is YamlList) {
        for (final member in workspace) {
          if (member is! String || p.isAbsolute(member)) continue;
          final memberPath = _resolveThroughExistingAncestor(
            p.normalize(p.join(directory.path, member)),
          );
          if (p.equals(memberPath, canonicalPackage.path)) {
            return Directory(directory.resolveSymbolicLinksSync());
          }
        }
      }
    }
    final parent = directory.parent;
    if (p.equals(parent.path, directory.path)) return canonicalPackage;
    directory = parent;
  }
}

/// Locates [packageName] through the active package configuration and verifies
/// the resolved directory's pubspec identity.
Directory locateConfiguredPackageRoot(String packageName, {Directory? start}) {
  var directory = (start ?? Directory.current).absolute;
  while (true) {
    final config = File(
      p.join(directory.path, '.dart_tool', 'package_config.json'),
    );
    if (config.existsSync()) {
      final Object? decoded;
      try {
        decoded = jsonDecode(config.readAsStringSync());
      } on Object catch (error) {
        throw TomgenException('Failed to parse ${config.path}: $error');
      }
      if (decoded is! Map || decoded['packages'] is! List) {
        throw TomgenException('${config.path} has no package list.');
      }
      for (final entry in (decoded['packages'] as List).whereType<Map>()) {
        if (entry['name'] != packageName || entry['rootUri'] is! String) {
          continue;
        }
        final rootUri = config.uri.resolve(entry['rootUri'] as String);
        final root = Directory.fromUri(rootUri);
        final canonical = Directory(root.resolveSymbolicLinksSync());
        final actual = readPubPackageName(
          File(p.join(canonical.path, 'pubspec.yaml')),
        );
        if (actual != packageName) {
          throw TomgenException(
            'Package configuration maps "$packageName" to ${canonical.path}, '
            'whose pubspec declares "$actual".',
          );
        }
        return canonical;
      }
      throw TomgenException(
        '${config.path} does not contain package "$packageName".',
      );
    }
    final parent = directory.parent;
    if (p.equals(parent.path, directory.path)) {
      throw TomgenException(
        'No package_config.json was found for package "$packageName".',
      );
    }
    directory = parent;
  }
}

String resolveProjectSourcePath({
  required Directory packageRoot,
  required Directory boundary,
  required String relativePath,
  required String description,
  bool mustExist = false,
}) {
  if (p.isAbsolute(relativePath)) {
    throw TomgenException('$description must be package-relative.');
  }
  final candidate = p.normalize(p.join(packageRoot.path, relativePath));
  return resolveContainedPath(
    root: boundary,
    relativePath: p.relative(candidate, from: boundary.path),
    description: description,
    mustExist: mustExist,
  );
}

bool isContainedBy(Directory root, String path) {
  final rootPath = root.resolveSymbolicLinksSync();
  return p.equals(rootPath, path) || p.isWithin(rootPath, path);
}

YamlMap _readPubspec(File pubspec) {
  final Object? document;
  try {
    document = loadYaml(pubspec.readAsStringSync());
  } on Object catch (error) {
    throw TomgenException('Failed to parse ${pubspec.path}: $error');
  }
  if (document is! YamlMap) {
    throw TomgenException('${pubspec.path} must contain a YAML map.');
  }
  return document;
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
