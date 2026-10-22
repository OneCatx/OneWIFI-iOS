import 'package:flutter/material.dart';

import '../../../core/format/local_time_text.dart';
import '../../../core/state/query_state.dart';
import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/console_layout.dart';
import '../../../design/widgets/one_status_hero.dart';
import '../../../design/widgets/system_controls.dart';
import '../domain/log_entry.dart';
import '../state/logs_controller.dart';

final class LogsScreen extends StatefulWidget {
  const LogsScreen({required this.controller, super.key});
  final LogsController controller;
  static const Key searchFieldKey = Key('logs-search-field');

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

final class _LogsScreenState extends State<LogsScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.load();
    });
  }

  @override
  void dispose() {
    widget.controller.stopWatching();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final state = widget.controller.entries;
      final logs = state.lastGoodData ?? const <LogEntry>[];
      final listing =
          state.status != QueryStatus.loading &&
          state.status != QueryStatus.failed &&
          logs.isNotEmpty;
      return CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: OneInsets.scroll(context),
            sliver: SliverMainAxisGroup(
              slivers: <Widget>[
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const OwPageHead(
                        title: '问题日志',
                        desc: '历史记录。失败后不会自动重试，点刷新再拉。',
                      ),
                      const SizedBox(height: OneSpacing.medium),
                      OwSection(
                        title: '过滤',
                        icon: Icons.filter_alt_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            ChoiceChipRow(
                              options: const <(String, String)>[
                                ('', '全部'),
                                ('warn', '警告及以上'),
                                ('error', '仅错误'),
                              ],
                              selected: widget.controller.level,
                              onSelected: (value) =>
                                  widget.controller.load(level: value),
                            ),
                            const SizedBox(height: OneSpacing.item),
                            TextField(
                              key: LogsScreen.searchFieldKey,
                              controller: _search,
                              decoration: const InputDecoration(
                                labelText: '搜索',
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (value) =>
                                  widget.controller.load(search: value),
                            ),
                            const SizedBox(height: OneSpacing.item),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton.icon(
                                onPressed: state.status == QueryStatus.loading
                                    ? null
                                    : () => widget.controller.load(
                                        search: _search.text,
                                      ),
                                icon: const SystemIcon(Icons.refresh),
                                label: const Text('刷新'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: OneSpacing.medium),
                      if (!listing)
                        OwSection(
                          title: '记录',
                          icon: Icons.article_outlined,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              if (state.status == QueryStatus.loading)
                                const OneStatusProgress(
                                  label: '正在加载日志',
                                  kind: OneProgressKind.linear,
                                )
                              else if (state.status == QueryStatus.failed)
                                const OneStatusHero(
                                  tone: OneStatusTone.critical,
                                  title: '日志不可用',
                                  message: '这次读取失败。点刷新再试，不要自动连打。',
                                )
                              else
                                const OneStatusHero(
                                  tone: OneStatusTone.attention,
                                  title: '没有匹配的日志',
                                  message: '换过滤条件或稍后再刷新。',
                                ),
                            ],
                          ),
                        )
                      else
                        const OwSection(
                          title: '记录',
                          icon: Icons.article_outlined,
                          child: SizedBox.shrink(),
                        ),
                    ],
                  ),
                ),
                if (listing)
                  SliverList.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final entry = logs[logs.length - 1 - index];
                      return Padding(
                        padding: const EdgeInsets.only(top: OneSpacing.item),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text(
                              '${entry.level.toUpperCase()} · ${formatLocalSecond(entry.time)}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            Text(entry.message),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
