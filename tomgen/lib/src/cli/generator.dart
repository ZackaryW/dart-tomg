import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../registry_document.dart';
import 'config.dart';
import 'emitter.dart';
import 'errors.dart';
import 'ownership.dart';
import 'project.dart';
import 'schema.dart';

final class GenerationResult {
  const GenerationResult({required this.project, required this.ownership});

  final TomgenProject project;
  final OwnershipResult ownership;
}

/// Coordinates all phase-one work before committing any generated file.
final class TomgenGenerator {
  TomgenGenerator({TomgenEmitter? emitter})
    : _emitter = emitter ?? TomgenEmitter();

  final TomgenEmitter _emitter;

  GenerationResult generate(Directory workingDirectory) {
    final project = TomgenProject.discover(workingDirectory);
    final config = TomgenConfig.load(project);
    final outputs = <TomgenOutput>[];
    for (final target in config.targets) {
      final sourceBytes = target.sourceFile.readAsBytesSync();
      final TomgRegistryDocument document;
      try {
        document = TomgRegistryDocument.parse(
          utf8.decode(sourceBytes),
          source: target.sourceRelative,
        );
      } on TomgDocumentException catch (error) {
        throw TomgenException('Target "${target.name}": ${error.message}');
      }
      final schema = TomgenSchema.infer(target, document);
      outputs.add(
        TomgenOutput(
          target.outputFile,
          _emitter.emit(
            schema,
            packageName: project.packageName,
            sourceDigest: target.isExternal
                ? 'sha256:${sha256.convert(sourceBytes)}'
                : null,
          ),
        ),
      );
    }
    final ownership = OwnershipStore(project.root).commit(outputs);
    return GenerationResult(project: project, ownership: ownership);
  }

  OwnershipResult clean(Directory workingDirectory) {
    final project = TomgenProject.discover(workingDirectory);
    return OwnershipStore(project.root).clean();
  }
}
