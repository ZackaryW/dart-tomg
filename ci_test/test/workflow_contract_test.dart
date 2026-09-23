import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  late String workflow;

  setUpAll(() {
    workflow = File(
      p.join(_workspaceRoot().path, '.github', 'workflows', 'ci.yml'),
    ).readAsStringSync();
  });

  test('CI workflow exposes every release verification gate', () {
    expect(_validateWorkflow(workflow), isEmpty);
  });

  test('contract detects weakened triggers, permissions, and gates', () {
    expect(
      _validateWorkflow(
        workflow.replaceFirst('  pull_request:\n', '  issue_comment:\n'),
      ),
      contains(contains('pull_request')),
    );
    expect(
      _validateWorkflow(
        workflow.replaceFirst('contents: read', 'contents: write'),
      ),
      contains(contains('contents: read')),
    );
    expect(
      _validateWorkflow(
        workflow.replaceFirst('dart test ci_test', 'dart test example'),
      ),
      contains(contains('dart test ci_test')),
    );
    expect(
      _validateWorkflow(
        workflow.replaceFirst("if: matrix.sdk == 'stable'", 'if: always()'),
      ),
      contains(contains('format only on Dart stable')),
    );
    expect(
      _validateWorkflow(
        workflow.replaceFirst(
          'dart pub -C tomgen publish --dry-run',
          'dart pub -C tomgen publish --dry-run --ignore-warnings',
        ),
      ),
      contains(contains('warning suppression')),
    );
  });
}

List<String> _validateWorkflow(String source) {
  final issues = <String>[];
  final Object? document;
  try {
    document = loadYaml(source);
  } on Object catch (error) {
    return <String>['Workflow YAML does not parse: $error'];
  }
  if (document is! YamlMap) return <String>['Workflow root must be a map.'];

  final triggers = document['on'];
  if (triggers is! YamlMap) {
    issues.add('Workflow must declare mapped triggers.');
  } else {
    for (final name in <String>['pull_request', 'push', 'workflow_dispatch']) {
      if (!triggers.containsKey(name)) issues.add('Missing $name trigger.');
    }
    final push = triggers['push'];
    final branches = push is YamlMap ? push['branches'] : null;
    if (branches is! YamlList || !branches.contains('main')) {
      issues.add('Push trigger must target main.');
    }
  }

  final permissions = document['permissions'];
  if (permissions is! YamlMap || permissions['contents'] != 'read') {
    issues.add('Workflow permissions must set contents: read.');
  }
  if (source.contains('pull_request_target')) {
    issues.add('Workflow must not use pull_request_target.');
  }

  final concurrency = document['concurrency'];
  if (concurrency is! YamlMap || concurrency['cancel-in-progress'] != true) {
    issues.add('Workflow must cancel superseded runs.');
  }

  final jobs = document['jobs'];
  final verify = jobs is YamlMap ? jobs['verify'] : null;
  if (verify is! YamlMap) return <String>[...issues, 'Missing verify job.'];
  if (verify['runs-on'] != 'ubuntu-latest') {
    issues.add('Verify job must run on ubuntu-latest.');
  }
  final strategy = verify['strategy'];
  final matrix = strategy is YamlMap ? strategy['matrix'] : null;
  final sdks = matrix is YamlMap ? matrix['sdk'] : null;
  if (sdks is! YamlList ||
      !sdks.contains('3.12.2') ||
      !sdks.contains('stable')) {
    issues.add('SDK matrix must contain 3.12.2 and stable.');
  }

  final steps = verify['steps'];
  if (steps is! YamlList) return <String>[...issues, 'Verify steps missing.'];
  final uses = <String>[];
  final commands = <String>[];
  final namedSteps = <String, YamlMap>{};
  for (final step in steps.whereType<YamlMap>()) {
    final action = step['uses'];
    if (action is String) uses.add(action);
    final run = step['run'];
    if (run is String) commands.add(run.trim());
    final name = step['name'];
    if (name is String) namedSteps[name] = step;
  }
  if (!uses.any((action) => action.startsWith('actions/checkout@'))) {
    issues.add('Missing actions/checkout step.');
  }
  if (!uses.contains('dart-lang/setup-dart@v1')) {
    issues.add('Missing dart-lang/setup-dart@v1 step.');
  }

  for (final command in <String>[
    'dart pub get',
    'dart format --output=none --set-exit-if-changed .',
    'dart analyze',
    'dart test tomg',
    'dart test tomgen',
    'dart test ci_test',
    'dart run tomgen build',
    'dart test',
    'git diff --exit-code -- example/lib/generated',
    'dart pub -C tomg publish --dry-run',
    'dart pub -C tomgen publish --dry-run',
  ]) {
    if (!commands.contains(command)) issues.add('Missing command: $command');
  }
  for (final name in <String>[
    'Dry-run tomg archive',
    'Dry-run tomgen archive',
  ]) {
    final condition = namedSteps[name]?['if'];
    if (condition is! String || !condition.contains("matrix.sdk == '3.12.2'")) {
      issues.add('$name must run only on Dart 3.12.2.');
    }
  }
  final formatCondition = namedSteps['Check formatting']?['if'];
  if (formatCondition is! String ||
      !formatCondition.contains("matrix.sdk == 'stable'")) {
    issues.add('Check formatting must format only on Dart stable.');
  }
  if (source.contains('--ignore-warnings') ||
      source.contains('--skip-validation')) {
    issues.add('Publish dry-runs must not use warning suppression.');
  }
  return issues;
}

Directory _workspaceRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    if (File(p.join(directory.path, 'pubspec.yaml')).existsSync() &&
        Directory(p.join(directory.path, 'tomg')).existsSync() &&
        Directory(p.join(directory.path, 'tomgen')).existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (p.equals(parent.path, directory.path)) {
      throw StateError('Could not locate the dart-tomg workspace.');
    }
    directory = parent;
  }
}
