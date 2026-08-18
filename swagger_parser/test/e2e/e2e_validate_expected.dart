// ignore_for_file: avoid_print
import 'dart:io';

import 'package:path/path.dart';

Future<void> main(List<String> args) async {
  try {
    final tests = Directory(args[0]);
    final template = Directory(args[1]);
    final scratch = Directory(args[2]);
    exit(await validateAll(tests, template, scratch));
  } on Object catch (e, stack) {
    print('USAGE: dir_with_e2e_tests validation_template_dir scratch_dir');
    print(e);
    print(stack);
    exit(1);
  }
}

Future<int> validateAll(
    Directory tests, Directory template, Directory scratch) async {
  await for (final root in expectedRoots(tests.list(recursive: true))) {
    await for (final f in root.list()) {
      if (f is File &&
          basename(f.path).startsWith('openapi') &&
          await validate(f, template, scratch) != 0) {
        return 1;
      }
    }
  }
  return 0;
}

Future<int> validate(File test, Directory template, Directory scratch) async {
  print('validating ${test.path}');
  // reset scratch
  if (scratch.existsSync()) {
    await scratch.delete(recursive: true);
  }
  await scratch.create();
  await copy(template, scratch);
  // await test.copy(join(scratch.path, basename(test.path)));
  // await copy(test, scratch);
  final pubspec = File(join(scratch.path, 'pubspec.yaml'));
  await pubspec.writeAsString((await pubspec.readAsString())
      .replaceFirst('openapi', test.absolute.path));
  // validate
  const commands = [
    ('dart', ['run', 'swagger_parser']),
    ('dart', ['run', 'build_runner', 'build', '--force-jit']),
    ('dart', ['analyze', '--no-fatal-warnings'])
  ];
  for (final (exec, args) in commands) {
    final ps = await Process.start(exec, args,
        workingDirectory: scratch.absolute.path,
        mode: ProcessStartMode.inheritStdio);
    if (await ps.exitCode != 0) {
      return 1;
    }
  }
  return 0;
}

Future<void> copy(Directory from, Directory to) async {
  await for (final f in from.list()) {
    if (f is File) {
      await f.copy(join(to.path, basename(f.path)));
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
