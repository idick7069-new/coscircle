import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/work.dart';
import '../../../core/repositories/work_repository.dart';
import '../../../shared/widgets/cos_ui.dart';

class WorkMultiSelector extends ConsumerStatefulWidget {
  const WorkMultiSelector({
    super.key,
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<WorkTag> selected;
  final ValueChanged<List<WorkTag>> onChanged;

  @override
  ConsumerState<WorkMultiSelector> createState() => _WorkMultiSelectorState();
}

class _WorkMultiSelectorState extends ConsumerState<WorkMultiSelector> {
  final _controller = TextEditingController();
  List<WorkTag> _suggestions = const [];
  bool _loading = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WorkSelectorLabel(
          label: widget.label,
          selectedCount: widget.selected.length,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: '搜尋作品或輸入新作品名',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
          ),
          textInputAction: TextInputAction.done,
          onChanged: _search,
          onSubmitted: _createAndSelect,
        ),
        if (widget.selected.isNotEmpty) ...[
          const SizedBox(height: 10),
          _SelectedWorkWrap(
            works: widget.selected,
            onRemove: (work) => widget.onChanged(
              widget.selected.where((item) => item != work).toList(),
            ),
          ),
        ],
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          _WorkSuggestionPanel(
            title: '可加入的作品',
            suggestions: _suggestions,
            onSelect: _select,
          ),
        ],
        if (_errorText != null) ...[
          const SizedBox(height: 8),
          _WorkErrorText(_errorText!),
        ],
        if (query.isNotEmpty && !_suggestions.any((work) => work.name == query))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: _loading
                  ? null
                  : () => _createAndSelect(_controller.text),
              icon: const Icon(Icons.add),
              label: Text('新增「$query」'),
            ),
          ),
      ],
    );
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _suggestions = const [];
        _errorText = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final results = await ref
          .read(workRepositoryProvider)
          .searchWorks(trimmed);
      if (!mounted || _controller.text.trim() != trimmed) return;
      setState(() {
        _suggestions = results
            .where((work) => !widget.selected.contains(work))
            .toList();
      });
    } catch (_) {
      if (!mounted || _controller.text.trim() != trimmed) return;
      setState(() {
        _suggestions = const [];
        _errorText = '作品搜尋失敗，請稍後再試';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createAndSelect(String value) async {
    final name = value.trim();
    if (name.isEmpty) return;
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final work = await ref.read(workRepositoryProvider).createWork(name);
      _select(work);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = '作品新增失敗，請稍後再試');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(WorkTag work) {
    if (!widget.selected.contains(work)) {
      widget.onChanged([...widget.selected, work]);
    }
    setState(() {
      _controller.clear();
      _suggestions = const [];
      _errorText = null;
    });
  }
}

class WorkSingleSelector extends ConsumerStatefulWidget {
  const WorkSingleSelector({
    super.key,
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final WorkTag? selected;
  final ValueChanged<WorkTag?> onChanged;

  @override
  ConsumerState<WorkSingleSelector> createState() => _WorkSingleSelectorState();
}

class _WorkSingleSelectorState extends ConsumerState<WorkSingleSelector> {
  final _controller = TextEditingController();
  List<WorkTag> _suggestions = const [];
  bool _loading = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final query = _controller.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WorkSelectorLabel(
          label: widget.label,
          selectedCount: selected == null ? 0 : 1,
        ),
        const SizedBox(height: 8),
        if (selected != null) ...[
          _SelectedWorkWrap(
            works: [selected],
            onRemove: (_) => widget.onChanged(null),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: '搜尋作品或輸入新作品名',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
          ),
          textInputAction: TextInputAction.done,
          onChanged: _search,
          onSubmitted: _createAndSelect,
        ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          _WorkSuggestionPanel(
            title: '選擇作品',
            suggestions: _suggestions,
            onSelect: _select,
          ),
        ],
        if (_errorText != null) ...[
          const SizedBox(height: 8),
          _WorkErrorText(_errorText!),
        ],
        if (query.isNotEmpty && !_suggestions.any((work) => work.name == query))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: _loading
                  ? null
                  : () => _createAndSelect(_controller.text),
              icon: const Icon(Icons.add),
              label: Text('新增「$query」'),
            ),
          ),
      ],
    );
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _suggestions = const [];
        _errorText = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final results = await ref
          .read(workRepositoryProvider)
          .searchWorks(trimmed);
      if (!mounted || _controller.text.trim() != trimmed) return;
      setState(() => _suggestions = results);
    } catch (_) {
      if (!mounted || _controller.text.trim() != trimmed) return;
      setState(() {
        _suggestions = const [];
        _errorText = '作品搜尋失敗，請稍後再試';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createAndSelect(String value) async {
    final name = value.trim();
    if (name.isEmpty) return;
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final work = await ref.read(workRepositoryProvider).createWork(name);
      _select(work);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = '作品新增失敗，請稍後再試');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(WorkTag work) {
    widget.onChanged(work);
    setState(() {
      _controller.clear();
      _suggestions = const [];
      _errorText = null;
    });
  }
}

class _WorkSelectorLabel extends StatelessWidget {
  const _WorkSelectorLabel({required this.label, required this.selectedCount});

  final String label;
  final int selectedCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final countLabel = selectedCount == 0
        ? '輸入作品名，快速建立坑單訊號'
        : '已選 $selectedCount 個作品';

    return Row(
      children: [
        CosIconBubble(
          icon: Icons.auto_awesome,
          color: scheme.primary,
          size: 34,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                countLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SelectedWorkWrap extends StatelessWidget {
  const _SelectedWorkWrap({required this.works, required this.onRemove});

  final List<WorkTag> works;
  final ValueChanged<WorkTag> onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final work in works)
          InputChip(
            avatar: Icon(Icons.check_circle, color: scheme.primary, size: 16),
            label: Text(work.name),
            onDeleted: () => onRemove(work),
            backgroundColor: scheme.primaryContainer.withValues(alpha: 0.46),
            deleteIconColor: scheme.onPrimaryContainer,
            side: BorderSide(color: scheme.primary.withValues(alpha: 0.24)),
          ),
      ],
    );
  }
}

class _WorkSuggestionPanel extends StatelessWidget {
  const _WorkSuggestionPanel({
    required this.title,
    required this.suggestions,
    required this.onSelect,
  });

  final String title;
  final List<WorkTag> suggestions;
  final ValueChanged<WorkTag> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(CosUi.radiusMd),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.58),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.saved_search, size: 17, color: scheme.secondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in suggestions.indexed)
                  CosReveal(
                    delay: Duration(milliseconds: 30 * entry.$1),
                    offset: const Offset(0, 6),
                    child: ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: Text(entry.$2.name),
                      onPressed: () => onSelect(entry.$2),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkErrorText extends StatelessWidget {
  const _WorkErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(CosUi.radiusMd),
        border: Border.all(color: scheme.error.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: scheme.error, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
