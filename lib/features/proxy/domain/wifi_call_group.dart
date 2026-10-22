/// Mihomo 延迟探测结果。HTTP 测不通不等于节点超时——WiFi Call 叶子经常过不了 gstatic。
enum WifiDelayKind { measured, timedOut, unknown }

final class WifiDelay {
  const WifiDelay.measured(this.ms) : kind = WifiDelayKind.measured;

  const WifiDelay.timedOut() : kind = WifiDelayKind.timedOut, ms = 0;

  const WifiDelay.unknown() : kind = WifiDelayKind.unknown, ms = 0;

  final WifiDelayKind kind;
  final int ms;

  @override
  bool operator ==(Object other) =>
      other is WifiDelay && other.kind == kind && other.ms == ms;

  @override
  int get hashCode => Object.hash(kind, ms);
}

/// Mihomo 里一组 WiFi Call Selector（如 `HK-WIFI Selector`）及其当前节点。
final class WifiCallGroup {
  const WifiCallGroup({
    required this.groupName,
    required this.countryCode,
    required this.countryName,
    required this.flagEmoji,
    required this.now,
    required this.aliveCount,
    required this.totalCount,
    required this.nodes,
  });

  final String groupName;
  final String countryCode;
  final String countryName;
  final String flagEmoji;
  final String now;
  final int aliveCount;
  final int totalCount;
  final List<WifiCallNode> nodes;

  WifiCallGroup withNow(String now) => WifiCallGroup(
    groupName: groupName,
    countryCode: countryCode,
    countryName: countryName,
    flagEmoji: flagEmoji,
    now: now,
    aliveCount: aliveCount,
    totalCount: totalCount,
    nodes: nodes,
  );

  WifiCallGroup withProbedDelay(String target, WifiDelay delay) {
    var changed = false;
    final next = <WifiCallNode>[];
    for (final node in nodes) {
      if (!_appliesDelay(target, node)) {
        next.add(node);
        continue;
      }
      changed = true;
      next.add(node.withProbedDelay(delay));
    }
    if (!changed) return this;
    return _copy(nodes: next);
  }

  /// 组 delay API 只回测通的叶子；没出现的名字按超时落盘。
  WifiCallGroup withProbedDelays(Map<String, WifiDelay> delays) {
    final next = <WifiCallNode>[
      for (final node in nodes)
        node.withProbedDelay(
          delays[node.name] ??
              delays[node.delayTarget] ??
              const WifiDelay.timedOut(),
        ),
    ];
    return _copy(nodes: next);
  }

  WifiCallGroup _copy({required List<WifiCallNode> nodes}) {
    return WifiCallGroup(
      groupName: groupName,
      countryCode: countryCode,
      countryName: countryName,
      flagEmoji: flagEmoji,
      now: now,
      aliveCount: nodes.where((node) => node.alive).length,
      totalCount: nodes.length,
      nodes: List<WifiCallNode>.unmodifiable(nodes),
    );
  }

  bool _appliesDelay(String target, WifiCallNode node) {
    if (node.matchesDelayTarget(target)) return true;
    if (target != groupName) return false;
    return node.name == now || node.delayTarget == now;
  }
}

final class WifiCallNode {
  const WifiCallNode({
    required this.name,
    required this.alive,
    this.delayMs = 0,
    this.probeName,
    this.delayProbed = false,
    this.delayFailed = false,
  });

  final String name;
  final bool alive;
  final int delayMs;
  final String? probeName;
  final bool delayProbed;
  final bool delayFailed;

  String get delayTarget =>
      probeName == null || probeName!.isEmpty ? name : probeName!;

  bool matchesDelayTarget(String target) {
    if (name == target || delayTarget == target) return true;
    return false;
  }

  WifiCallNode withProbedDelay(WifiDelay delay) {
    switch (delay.kind) {
      case WifiDelayKind.measured:
        return WifiCallNode(
          name: name,
          alive: true,
          delayMs: delay.ms,
          probeName: probeName,
          delayProbed: true,
        );
      case WifiDelayKind.timedOut:
        return WifiCallNode(
          name: name,
          alive: false,
          probeName: probeName,
          delayProbed: true,
          delayFailed: true,
        );
      case WifiDelayKind.unknown:
        return WifiCallNode(
          name: name,
          alive: alive,
          delayMs: delayMs,
          probeName: probeName,
          delayProbed: true,
          delayFailed: delayFailed,
        );
    }
  }
}
