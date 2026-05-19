import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/work.dart';
import '../../../core/repositories/work_repository.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.label,
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
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final work in widget.selected)
                InputChip(
                  label: Text(work.name),
                  onDeleted: () => widget.onChanged(
                    widget.selected.where((item) => item != work).toList(),
                  ),
                ),
            ],
          ),
        ],
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final work in _suggestions)
                ActionChip(
                  label: Text(work.name),
                  onPressed: () => _select(work),
                ),
            ],
          ),
        ],
        if (_errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            _errorText!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
        if (_controller.text.trim().isNotEmpty &&
            !_suggestions.any((work) => work.name == _controller.text.trim()))
          TextButton.icon(
            onPressed: _loading
                ? null
                : () => _createAndSelect(_controller.text),
            icon: const Icon(Icons.add),
            label: Text('新增「${_controller.text.trim()}」'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selected != null) ...[
          InputChip(
            label: Text(selected.name),
            onDeleted: () => widget.onChanged(null),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.label,
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
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final work in _suggestions)
                ActionChip(
                  label: Text(work.name),
                  onPressed: () => _select(work),
                ),
            ],
          ),
        ],
        if (_errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            _errorText!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
        if (_controller.text.trim().isNotEmpty &&
            !_suggestions.any((work) => work.name == _controller.text.trim()))
          TextButton.icon(
            onPressed: _loading
                ? null
                : () => _createAndSelect(_controller.text),
            icon: const Icon(Icons.add),
            label: Text('新增「${_controller.text.trim()}」'),
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
