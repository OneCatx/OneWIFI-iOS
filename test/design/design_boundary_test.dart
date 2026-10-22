/// 设计层边界棘轮测试（ratchet）。
///
/// `lib/design/one/` 是从 OneIms Ultra 只读迁移来的视觉原件（设计层内部件）；
/// `lib/design/widgets/`、`lib/design/tokens/`、`lib/design/theme/` 才是
/// OneWIFI 自己的门面层。业务代码只能用门面。2026-09-06 已决策把 `design/one`
/// 定为内部层，原先 6 个直引文件全部改到门面，白名单收为空集。
///
/// - 禁止变差：任何非 design 文件新增 `design/one/` import，第一个用例失败并打印
///   违规条目。需要新能力时给门面（widgets / tokens / theme）补别名或参数，
///   不要往白名单加行——除非附带明确的设计决策。
/// - 白名单只会缩小：若将来出于设计决策临时放行某文件，条目一旦过期（文件已不再有
///   该引用），第二个用例会失败并指出该删哪行，保证不会残留。
///
/// 匹配口径：递归读取 `lib/**/*.dart`（排除 `lib/design/` 自身），按行匹配
/// `import` / `export` 指令中 URI 含 `design/one/` 的行，相对路径
/// （`../design/one/x.dart`）与包路径（`package:onewifi_android/design/one/x.dart`）
/// 两种写法都覆盖；注释掉的 import 不算。路径统一换成 `/` 分隔以兼容 Windows。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 白名单：文件路径（相对项目根、`/` 分隔）→ 该文件允许直接引用的
/// `design/one/` 文件名。当前为空；不要加行。
const Map<String, Set<String>> _allowedDesignOneImports =
    <String, Set<String>>{};

/// 匹配 `import` / `export` 指令中 URI 含 `design/one/` 的行；
/// 第 1 组是 `design/one/` 之后的文件名（如 `glass.dart`）。
final RegExp _designOneDirective = RegExp(
  r'''^\s*(?:import|export)\s+['"][^'"]*design/one/([^'"]+)['"]''',
);

void main() {
  late Map<String, Set<String>> actualImports;

  setUpAll(() {
    final lib = Directory('lib');
    expect(
      lib.existsSync(),
      isTrue,
      reason: 'design_boundary_test must run from the package root',
    );
    actualImports = _collectDesignOneImports(lib);
  });

  test('app sources import design/one only where the allowlist permits', () {
    final violations = <String>[];
    for (final entry in actualImports.entries) {
      final allowed = _allowedDesignOneImports[entry.key] ?? const <String>{};
      for (final name in entry.value) {
        if (!allowed.contains(name)) {
          violations.add('${entry.key} imports design/one/$name');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Business code must go through lib/design/widgets, tokens or theme '
          'instead of design/one internals. Fix the import, or extend the '
          'allowlist in this file only with an explicit design decision.',
    );
  });

  test('allowlist entries are still real so the ratchet only tightens', () {
    final stale = <String>[];
    for (final entry in _allowedDesignOneImports.entries) {
      final current = actualImports[entry.key] ?? const <String>{};
      for (final name in entry.value) {
        if (!current.contains(name)) {
          final suffix = File(entry.key).existsSync() ? '' : ' (file is gone)';
          stale.add('${entry.key} no longer imports design/one/$name$suffix');
        }
      }
    }

    expect(
      stale,
      isEmpty,
      reason:
          'These allowlist entries are obsolete. Delete them from '
          '_allowedDesignOneImports so the ratchet tightens.',
    );
  });
}

/// 收集 `lib/`（排除 `lib/design/`）下每个 `.dart` 文件直接引用的
/// `design/one/*` 文件名；没有引用的文件不出现在结果里。
Map<String, Set<String>> _collectDesignOneImports(Directory lib) {
  final files =
      lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final result = <String, Set<String>>{};
  for (final file in files) {
    final path = file.path.replaceAll('\\', '/');
    if (path.startsWith('lib/design/')) continue;
    for (final line in file.readAsLinesSync()) {
      final match = _designOneDirective.firstMatch(line);
      if (match != null) {
        result.putIfAbsent(path, () => <String>{}).add(match.group(1)!);
      }
    }
  }
  return result;
}
