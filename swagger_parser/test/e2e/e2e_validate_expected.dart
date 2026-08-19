// ignore_for_file: avoid_print
import 'dart:io';

import 'package:path/path.dart';

Future<void> main(List<String> args) async {
  try {
    final library = Directory(args[0]);
    final tests = Directory(args[1]);
    final template = Directory(args[2]);
    final scratch = Directory(args[3]);
    exit(await validateAll(library, tests, template, scratch));
  } on Object catch (e, stack) {
    print('USAGE: library dir_with_e2e_tests validation_template_dir scratch_dir');
    print(e);
    print(stack);
    exit(1);
  }
}

Future<int> validateAll(
    Directory library, Directory tests, Directory template, Directory scratch) async {
  final concurrency = Platform.numberOfProcessors;
  var activeFutures = 0;
  final futures = <(String, Future<int>)>[];
  await for (final root in expectedRoots(tests.list(recursive: true))) {
    await for (final f in root.list()) {
      if (f is File &&
          (basename(f.path).contains('json') ||
              basename(f.path).contains('yaml'))) {
        while (activeFutures >= concurrency) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        activeFutures += 1;
        futures.add((
          f.path,
          validate(library, f, template, await scratch.createTemp())
              .whenComplete(() => activeFutures -= 1)
        ));
      }
    }
  }
  final results = await Future.wait(futures.map((x) async {
    return (x.$1, await x.$2);
  }));
  final numFailures = results.where((x) => x.$2 == 0).length;
  print('$numFailures / ${results.length} passed');
  print('failures:');
  print(
      '    ${results.where((x) => x.$2 != 0).map((x) => x.$1).join('\n    ')}');
  return numFailures == 0 ? 0 : 1;
}

Future<int> validate(Directory library, File test, Directory template, Directory scratch) async {
  print('validating ${test.path}');
  // reset scratch
  if (scratch.existsSync()) {
    await scratch.delete(recursive: true);
  }
  await scratch.create(recursive: true);
  await copy(template, scratch);
  final pubspec = File(join(scratch.path, 'pubspec.yaml'));
  await pubspec.writeAsString((await pubspec.readAsString())
      .replaceFirst('openapi', test.absolute.path).replaceFirst('localpath', library.absolute.path));
  // validate
  const commands = [
    ('dart', ['run', 'swagger_parser']),
    ('dart', ['run', 'build_runner', 'build', '--force-jit']),
    ('dart', ['analyze', '--no-fatal-warnings'])
  ];
  for (final (exec, args) in commands) {
    final ps = await Process.run(
      exec,
      args,
      workingDirectory: scratch.absolute.path,
    );
    if (ps.exitCode != 0) {
      print('$exec ${args.join(' ')} failed for ${test.path}');
      print('===stdout===');
      print(ps.stdout);
      print('===stderr===');
      print(ps.stderr);
      return 1;
    }
  }
  return 0;
}

Future<void> copy(Directory from, Directory to) async {
  await for (final f in from.list()) {
    if (f is File) {
      await f.copy(join(to.path, basename(f.path).replaceFirst('.template', '')));
    } else if (f is Directory) {
      final newDir = Directory(join(to.path, basename(f.path)));
      await newDir.create();
      await copy(f, newDir);
    }
  }
}

Stream<Directory> expectedRoots(Stream<FileSystemEntity> s) {
  return s
      .where((e) => e is Directory)
      .cast<Directory>()
      .where((dir) => dir.path.endsWith('expected_files'))
      .map((dir) => dir.parent);
}
