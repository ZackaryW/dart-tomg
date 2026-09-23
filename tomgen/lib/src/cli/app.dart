import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';

import 'errors.dart';
import 'generator.dart';
import 'initializer.dart';

enum TomgenCommand { init, generate, build, clean, help }

final class TomgenInvocation {
  const TomgenInvocation(
    this.command,
    this.forwardedArguments, {
    this.initRequest,
  });

  final TomgenCommand command;
  final List<String> forwardedArguments;
  final TomgenInitRequest? initRequest;

  static TomgenInvocation parse(List<String> arguments) {
    if (arguments.isEmpty ||
        arguments.first == 'help' ||
        arguments.first == '--help' ||
        arguments.first == '-h') {
      return const TomgenInvocation(TomgenCommand.help, <String>[]);
    }
    final command = switch (arguments.first) {
      'init' => TomgenCommand.init,
      'generate' => TomgenCommand.generate,
      'build' => TomgenCommand.build,
      'clean' => TomgenCommand.clean,
      final unknown => throw TomgenException('Unknown command "$unknown".'),
    };
    final tail = arguments.sublist(1);
    final separator = tail.indexOf('--');
    final ownArguments = separator < 0 ? tail : tail.sublist(0, separator);
    final forwarded = separator < 0
        ? const <String>[]
        : tail.sublist(separator + 1);
    final parser = ArgParser(allowTrailingOptions: false)
      ..addFlag('help', abbr: 'h', negatable: false);
    if (command == TomgenCommand.init) {
      parser
        ..addOption('source')
        ..addOption('target')
        ..addOption('model')
        ..addOption('key')
        ..addOption('output');
      _rejectDuplicateInitOptions(ownArguments);
    }
    final ArgResults parsed;
    try {
      parsed = parser.parse(ownArguments);
    } on FormatException catch (error) {
      throw TomgenException(error.message);
    }
    if (parsed.rest.isNotEmpty) {
      throw TomgenException(
        'Unexpected arguments for ${arguments.first}: ${parsed.rest.join(' ')}',
      );
    }
    if (parsed.flag('help')) {
      return const TomgenInvocation(TomgenCommand.help, <String>[]);
    }
    if (command != TomgenCommand.build && forwarded.isNotEmpty) {
      throw TomgenException(
        'Only the build command accepts arguments after --.',
      );
    }
    if (command == TomgenCommand.init) {
      final names = <String>['source', 'target', 'model', 'key'];
      final present = names.where(parsed.wasParsed).toList();
      final custom = present.isNotEmpty || parsed.wasParsed('output');
      if (!custom) {
        return const TomgenInvocation(
          TomgenCommand.init,
          <String>[],
          initRequest: TomgenInitRequest.starter(),
        );
      }
      final missing = names.where((name) => !parsed.wasParsed(name)).toList();
      if (missing.isNotEmpty) {
        throw TomgenException(
          'Custom init requires ${names.map((name) => '--$name').join(', ')}; '
          'missing ${missing.map((name) => '--$name').join(', ')}.',
        );
      }
      return TomgenInvocation(
        TomgenCommand.init,
        const <String>[],
        initRequest: TomgenInitRequest(
          source: parsed.option('source')!,
          target: parsed.option('target')!,
          model: parsed.option('model')!,
          key: parsed.option('key')!,
          output: parsed.option('output') ?? 'lib/generated',
          createStarterSource: false,
        ),
      );
    }
    return TomgenInvocation(command, List.unmodifiable(forwarded));
  }

  static void _rejectDuplicateInitOptions(List<String> arguments) {
    for (final name in <String>['source', 'target', 'model', 'key', 'output']) {
      final count = arguments
          .where(
            (argument) =>
                argument == '--$name' || argument.startsWith('--$name='),
          )
          .length;
      if (count > 1) {
        throw TomgenException('Option --$name may be specified only once.');
      }
    }
  }
}

typedef TomgenProcessRunner =
    Future<int> Function(
      String executable,
      List<String> arguments, {
      required String workingDirectory,
    });

/// User-facing command dispatcher for the tomgen executable.
final class TomgenApp {
  TomgenApp({
    TomgenGenerator? generator,
    TomgenInitializer? initializer,
    TomgenProcessRunner? processRunner,
    Directory? workingDirectory,
    StringSink? out,
    StringSink? err,
  }) : _generator = generator ?? TomgenGenerator(),
       _initializer = initializer ?? TomgenInitializer(),
       _processRunner = processRunner ?? _runProcess,
       _workingDirectory = workingDirectory ?? Directory.current,
       _out = out ?? stdout,
       _err = err ?? stderr;

  final TomgenGenerator _generator;
  final TomgenInitializer _initializer;
  final TomgenProcessRunner _processRunner;
  final Directory _workingDirectory;
  final StringSink _out;
  final StringSink _err;

  Future<int> run(List<String> arguments) async {
    try {
      final invocation = TomgenInvocation.parse(arguments);
      switch (invocation.command) {
        case TomgenCommand.help:
          _out.write(_usage);
          return 0;
        case TomgenCommand.init:
          final result = _initializer.initialize(
            _workingDirectory,
            invocation.initRequest!,
          );
          _out.writeln('Initialized package at ${result.project.root.path}.');
          if (result.created.isNotEmpty) {
            _out.writeln('Created or updated:');
            for (final path in result.created) {
              _out.writeln('  $path');
            }
          }
          if (result.reused.isNotEmpty) {
            _out.writeln('Reused:');
            for (final path in result.reused) {
              _out.writeln('  $path');
            }
          }
          _out.writeln('Next: dart run tomgen build');
          return 0;
        case TomgenCommand.generate:
          final result = _generator.generate(_workingDirectory);
          _printGeneration(result);
          return 0;
        case TomgenCommand.clean:
          final result = _generator.clean(_workingDirectory);
          _out.writeln('Removed ${result.deleted} tomgen model file(s).');
          return 0;
        case TomgenCommand.build:
          final result = _generator.generate(_workingDirectory);
          _printGeneration(result);
          _out.writeln('Running build_runner...');
          return await _processRunner(Platform.resolvedExecutable, <String>[
            'run',
            'build_runner',
            'build',
            ...invocation.forwardedArguments,
          ], workingDirectory: result.project.root.path);
      }
    } on TomgenException catch (error) {
      _err.writeln('tomgen: ${error.message}');
      return 1;
    } on FileSystemException catch (error) {
      _err.writeln('tomgen: ${error.message}');
      return 1;
    }
  }

  void _printGeneration(GenerationResult result) {
    final ownership = result.ownership;
    _out.writeln(
      'Generated ${ownership.written} model file(s); '
      '${ownership.unchanged} unchanged; ${ownership.deleted} stale removed.',
    );
  }

  static Future<int> _runProcess(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      mode: ProcessStartMode.inheritStdio,
    );
    return process.exitCode;
  }
}

const String _usage = '''
Generate typed Dart models and const registries from TOML.

Usage: dart run tomgen <command> [options]

Commands:
  init      Create g.toml and configure the first TOML target.
  generate  Generate annotated Dart model libraries from g.toml.
  build     Generate models, then run dart run build_runner build.
  clean     Remove unchanged phase-one files owned by tomgen.
  help      Show this help.

Custom initialization:
  dart run tomgen init --source <path> --target <name> --model <name>
    --key <field> [--output <path>]

Build runner arguments:
  dart run tomgen build -- <build_runner arguments>
''';
