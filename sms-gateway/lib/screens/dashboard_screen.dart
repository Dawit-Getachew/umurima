import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/api_service.dart';
import '../services/background_service.dart';
import '../services/queue_service.dart';
import '../services/sms_service.dart';

/// How the backend produced an answer, as the operator sees it.
class AnswerSource {
  const AnswerSource(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  static AnswerSource of(String? source) {
    switch (source) {
      case 'faq':
        return const AnswerSource('Verified answer', Icons.verified, Color(0xFF2E7D32));
      case 'cache':
        return const AnswerSource('Cached', Icons.bolt, Color(0xFF00838F));
      case 'ai':
        return const AnswerSource('AI answer', Icons.auto_awesome, Color(0xFF3949AB));
      case 'triage':
        return const AnswerSource('Urgent: sent to expert', Icons.warning_amber, Color(0xFFC62828));
      case 'offline':
        return const AnswerSource('From notes, offline', Icons.cloud_off, Color(0xFFEF6C00));
      case 'greeting':
        return const AnswerSource('Welcome', Icons.waving_hand, Color(0xFF6D4C41));
      case 'busy':
        return const AnswerSource('Asked to retry', Icons.hourglass_empty, Color(0xFF757575));
      default:
        return const AnswerSource('Reply', Icons.sms, Color(0xFF546E7A));
    }
  }
}

class DashboardScreen extends StatefulWidget {
  /// [live] is false in widget tests, which have no SMS radio, plugins or network.
  const DashboardScreen({super.key, this.live = true});

  final bool live;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final SmsService _smsService = SmsService();
  final ApiClient _api = ApiClient();
  Timer? _refreshTimer;
  Timer? _healthTimer;

  bool _isListening = false;
  bool _toggling = false;
  bool? _backendOnline; // null while the first check runs
  Map<String, dynamic> _health = const {};
  List<Map<String, dynamic>> _messages = const [];
  String _filter = 'all';
  String _search = '';

  @override
  void initState() {
    super.initState();
    if (!widget.live) return;
    _refresh();
    _checkBackend();
    _resumeIfRunning();
    // The background isolate answers SMS while this screen is open, so poll the
    // queue to show its work as it happens.
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
    _healthTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkBackend());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _healthTimer?.cancel();
    _smsService.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final rows = await QueueService.instance.getAllIncomingMessages();
      if (!mounted) return;
      setState(() => _messages = rows);
    } catch (_) {
      // the queue is unavailable only in tests and on non-Android platforms
    }
  }

  Future<void> _checkBackend() async {
    final result = await _api.health();
    if (!mounted) return;
    setState(() {
      _backendOnline = result.success;
      _health = result.data is Map ? Map<String, dynamic>.from(result.data as Map) : const {};
    });
  }

  /// The gateway keeps running after the app is closed; reflect that on reopen and
  /// re-attach the foreground listener so SMS arriving now still show up live.
  Future<void> _resumeIfRunning() async {
    if (!await isBackgroundServiceRunning() || !mounted) return;
    setState(() => _isListening = true);
    await _smsService.startListening(onMessageReceived: (_, _) => _refresh());
  }

  Future<void> _toggleGateway() async {
    setState(() => _toggling = true);
    try {
      if (_isListening) {
        _smsService.stopListening();
        await stopBackgroundService();
        setState(() => _isListening = false);
        _snack('Gateway stopped. Farmers\' SMS will not be answered.');
        return;
      }
      if (!await _smsService.requestPermissions()) {
        _snack('SMS permission is needed to receive and answer farmers.');
        return;
      }
      await startBackgroundService();
      await _smsService.startListening(onMessageReceived: (_, _) => _refresh());
      setState(() => _isListening = true);
      _snack('Gateway running. Farmers can now send SMS to this phone.');
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _retry(Map<String, dynamic> item) async {
    final id = item['id'] as int?;
    if (id == null) return;
    await QueueService.instance.markIncomingPending(id, 'Retry requested by operator');
    await _refresh();
    _snack(_isListening
        ? 'Queued. The gateway retries within 15 seconds.'
        : 'Queued. Start the gateway to send it.');
  }

  Future<void> _askTestQuestion() async {
    final question = await showDialog<String>(
      context: context,
      builder: (context) => const _TestQuestionDialog(),
    );
    if (question == null || question.trim().isEmpty || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final result = await _api.uploadIncoming(
      {'sender': '+250700000000', 'body': question.trim()},
    );
    if (!mounted) return;
    Navigator.of(context).pop();

    final data = result.data is Map ? result.data as Map : const {};
    final source = AnswerSource.of(data['source'] as String?);
    final reply = result.success
        ? (data['message']?.toString() ?? 'No reply text')
        : 'Backend unreachable: ${result.message}';
    final notes = (data['sources'] is List) ? (data['sources'] as List).join(', ') : '';

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Umurima AI would reply'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Farmer: ${question.trim()}',
                  style: const TextStyle(fontStyle: FontStyle.italic)),
              const SizedBox(height: 12),
              _ReplyBubble(text: reply, source: result.success ? source : null),
              const SizedBox(height: 8),
              Text('${reply.length} characters, ${_segments(reply)} SMS',
                  style: Theme.of(context).textTheme.bodySmall),
              if (notes.isNotEmpty)
                Text('Based on notes: $notes', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text('Test only: no SMS was sent.', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      ),
    );
    _checkBackend();
  }

  static int _segments(String text) => text.length <= 160 ? 1 : (text.length / 153).ceil();

  List<Map<String, dynamic>> get _visible {
    return _messages.where((m) {
      final status = m['status'] as String? ?? '';
      final matches = switch (_filter) {
        'replied' => status == 'replied',
        'waiting' => status == 'pending_upload' || status == 'uploading' || status == 'uploaded',
        'failed' => status == 'failed',
        _ => true,
      };
      return matches && (_search.isEmpty || (m['sender'] ?? '').toString().contains(_search));
    }).toList();
  }

  int _count(bool Function(String status) test) =>
      _messages.where((m) => test(m['status'] as String? ?? '')).length;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = _visible;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Umurima AI Gateway'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _refresh();
              _checkBackend();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _askTestQuestion,
        icon: const Icon(Icons.quiz_outlined),
        label: const Text('Test a question'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _refresh();
          await _checkBackend();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            _GatewayCard(
              listening: _isListening,
              busy: _toggling,
              onToggle: _toggleGateway,
            ),
            const SizedBox(height: 12),
            _BackendCard(online: _backendOnline, health: _health),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatTile(label: 'Received', value: _messages.length, color: scheme.primary),
                _StatTile(
                  label: 'Answered',
                  value: _count((s) => s == 'replied'),
                  color: const Color(0xFF2E7D32),
                ),
                _StatTile(
                  label: 'Waiting',
                  value: _count((s) => s == 'pending_upload' || s == 'uploading' || s == 'uploaded'),
                  color: const Color(0xFFEF6C00),
                ),
                _StatTile(
                  label: 'Failed',
                  value: _count((s) => s == 'failed'),
                  color: const Color(0xFFC62828),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Farmer conversations', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final (value, label) in const [
                  ('all', 'All'),
                  ('replied', 'Answered'),
                  ('waiting', 'Waiting'),
                  ('failed', 'Failed'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _filter == value,
                    onSelected: (_) => setState(() => _filter = value),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search phone number',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
              onChanged: (v) => setState(() => _search = v.trim()),
            ),
            const SizedBox(height: 12),
            if (visible.isEmpty)
              const _EmptyState()
            else
              for (final item in visible) _ConversationCard(item: item, onRetry: () => _retry(item)),
          ],
        ),
      ),
    );
  }
}

class _GatewayCard extends StatelessWidget {
  const _GatewayCard({required this.listening, required this.busy, required this.onToggle});

  final bool listening;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final color = listening ? const Color(0xFF2E7D32) : const Color(0xFF757575);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(listening ? Icons.sensors : Icons.sensors_off, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listening ? 'Gateway running' : 'Gateway stopped',
                    style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    listening
                        ? 'Farmer SMS are answered automatically, even with the app closed.'
                        : 'Start it to answer farmers who SMS this phone.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            busy
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : FilledButton(
                    onPressed: onToggle,
                    style: listening
                        ? FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828))
                        : null,
                    child: Text(listening ? 'Stop' : 'Start gateway'),
                  ),
          ],
        ),
      ),
    );
  }
}

class _BackendCard extends StatelessWidget {
  const _BackendCard({required this.online, required this.health});

  final bool? online;
  final Map<String, dynamic> health;

  @override
  Widget build(BuildContext context) {
    final color = switch (online) {
      true => const Color(0xFF2E7D32),
      false => const Color(0xFFC62828),
      null => const Color(0xFF757575),
    };
    final status = switch (online) {
      true => 'AI backend online',
      false => 'AI backend unreachable: messages wait in the queue',
      null => 'Checking AI backend...',
    };
    final bySource = health['answers_by_source'] is Map
        ? Map<String, dynamic>.from(health['answers_by_source'] as Map)
        : const <String, dynamic>{};
    final small = Theme.of(context).textTheme.bodySmall;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 12, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(status, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(ApiConfig.baseUrl, style: small),
            if (online == true) ...[
              const SizedBox(height: 8),
              Text(
                '${health['knowledge_chunks'] ?? '-'} knowledge notes · '
                '${health['verified_answers'] ?? '-'} verified answers · '
                '${health['cached_answers'] ?? '-'} cached answers',
                style: small,
              ),
              if (bySource.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final entry in bySource.entries)
                      _SourceChip(source: AnswerSource.of(entry.key), count: entry.value),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.source, this.count});

  final AnswerSource source;
  final Object? count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: source.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(source.icon, size: 14, color: source.color),
          const SizedBox(width: 4),
          Text(
            count == null ? source.label : '${source.label}: $count',
            style: TextStyle(fontSize: 12, color: source.color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Text('$value',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
              const SizedBox(height: 2),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplyBubble extends StatelessWidget {
  const _ReplyBubble({required this.text, this.source});

  final String text;
  final AnswerSource? source;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text),
          if (source != null) ...[
            const SizedBox(height: 6),
            _SourceChip(source: source!),
          ],
        ],
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({required this.item, required this.onRetry});

  final Map<String, dynamic> item;
  final VoidCallback onRetry;

  static String _time(String? iso) {
    final parsed = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (parsed == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final sameDay = parsed.year == now.year && parsed.month == now.month && parsed.day == now.day;
    final clock = '${two(parsed.hour)}:${two(parsed.minute)}';
    return sameDay ? clock : '${two(parsed.day)}/${two(parsed.month)} $clock';
  }

  @override
  Widget build(BuildContext context) {
    final status = item['status'] as String? ?? 'unknown';
    Map<String, dynamic> payload = const {};
    try {
      payload = jsonDecode(item['payload'] as String? ?? '{}') as Map<String, dynamic>;
    } catch (_) {}
    final reply = payload['reply'] is Map ? payload['reply'] as Map : null;
    final error = item['last_error'] as String?;

    final (statusLabel, statusColor, statusIcon) = switch (status) {
      'replied' => ('Answered', const Color(0xFF2E7D32), Icons.done_all),
      'failed' => ('Failed', const Color(0xFFC62828), Icons.error_outline),
      'uploading' => ('Thinking', const Color(0xFF3949AB), Icons.sync),
      'uploaded' => ('Sending', const Color(0xFF3949AB), Icons.send),
      _ => ('Waiting for network', const Color(0xFFEF6C00), Icons.schedule),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_outline, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(item['sender']?.toString() ?? 'unknown',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                Text(_time(item['created_at'] as String?),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 6),
            Text(item['body']?.toString() ?? '', style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 8),
            if (reply != null)
              _ReplyBubble(
                text: reply['message']?.toString() ?? '',
                source: AnswerSource.of(reply['source'] as String?),
              ),
            if (reply == null && error != null && status != 'replied')
              Text(error, style: TextStyle(fontSize: 12, color: statusColor)),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(statusIcon, size: 16, color: statusColor),
                const SizedBox(width: 4),
                Text(statusLabel,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 12)),
                const Spacer(),
                if (status == 'failed')
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.replay, size: 16),
                    label: const Text('Retry'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.forum_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 8),
          const Text('No farmer messages yet'),
          const SizedBox(height: 4),
          Text(
            'Start the gateway, then send an SMS question to this phone\nfrom any basic phone.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _TestQuestionDialog extends StatefulWidget {
  const _TestQuestionDialog();

  @override
  State<_TestQuestionDialog> createState() => _TestQuestionDialogState();
}

class _TestQuestionDialogState extends State<_TestQuestionDialog> {
  final TextEditingController _controller = TextEditingController();

  static const _examples = [
    'When should I plant maize?',
    'My coffee yield has dropped, why?',
    'Ni ryari natera ibishyimbo?',
    'My cow is not eating and has fever',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Test a farmer question'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 160,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Type as a farmer would SMS, in English or Kinyarwanda',
                border: OutlineInputBorder(),
              ),
            ),
            const Text('Examples', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final example in _examples)
                  ActionChip(
                    label: Text(example, style: const TextStyle(fontSize: 12)),
                    onPressed: () => setState(() => _controller.text = example),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Ask'),
        ),
      ],
    );
  }
}
