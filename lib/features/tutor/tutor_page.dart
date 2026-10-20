// «AI ustoz» (o'quvchi): mavzuni tushuntiradi va yo'naltiradi, tayyor javobni bermaydi. Test davomida ishlamaydi
// (ilova test oynasi ochiqligini biladi, server ham tekshiradi). API: ai/status, ai/chat, ai/conversations.
// 3.1: xuddi shu oyna xodimlar uchun «AI yordamchi» (kind: staff) — ai/status → staff.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../student/my_tests_page.dart';

const List<String> _suggestions = <String>[
  'Kvadrat tenglamani qanday yechaman?',
  'Present Perfect qachon ishlatiladi?',
  'Fotosintezni oddiy tilda tushuntir',
  'Mening yechimimni tekshir: 2x + 6 = 14, x = 5',
];

const List<String> _staffSuggestions = <String>[
  "Qarzdor ota-onaga muloyim eslatma matnini yozib ber",
  "7-sinf uchun kasrlar mavzusida 10 ta test savoli tuz",
  "Ota-onalar majlisi uchun qisqa reja tuz",
  "Yangi guruh ochilishi haqida Telegram e'loni yoz",
];

/// Xodimlar uchun AI yordamchi (3.1): o'sha chat, kind = staff.
class StaffAssistantPage extends StatelessWidget {
  const StaffAssistantPage({super.key});

  @override
  Widget build(BuildContext context) => const TutorPage(staff: true);
}

class TutorPage extends StatefulWidget {
  const TutorPage({super.key, this.staff = false});

  /// true — xodim yordamchisi (kind: staff), false — o'quvchi ustozi (kind: tutor).
  final bool staff;

  @override
  State<TutorPage> createState() => _TutorPageState();
}

class _TutorPageState extends State<TutorPage> {
  Map<String, dynamic>? _status;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _status = null;
      _error = null;
    });
    try {
      final status = asMap(await AppScope.read(context).api.get('ai/status'));
      if (mounted) setState(() => _status = status);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final title = widget.staff ? tr('AI yordamchi') : tr('AI ustoz');
    if (status != null && status[widget.staff ? 'staff' : 'tutor'] == true) {
      return _TutorChat(staff: widget.staff, remaining: status['remaining'] == null ? null : asInt(status['remaining']));
    }
    final error = _error;
    Widget body;
    if (error is ApiException && error.isForbidden) {
      body = ForbiddenState(details: error.message, onRetry: _load);
    } else if (error != null) {
      body = ErrorState(message: errorText(error), onRetry: _load);
    } else if (status == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = Center(
        child: EmptyState(
          icon: Icons.auto_awesome_outlined,
          text: widget.staff
              ? tr("AI yordamchi tashkilotingizda yoqilmagan yoki oylik limit tugagan. Direktor uni sozlamalarda yoqishi mumkin.")
              : tr("AI ustoz tashkilotingizda yoqilmagan. O'qituvchingiz yoki markaz ma'muriyatidan so'rang."),
          action: OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(tr('Qayta urinish'))),
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: Text(title)), body: body);
  }
}

class _Message {
  _Message(this.role, this.content, {this.failed = false});

  final String role;
  final String content;
  final bool failed;

  bool get mine => role == 'user';
}

class _TutorChat extends StatefulWidget {
  const _TutorChat({required this.remaining, this.staff = false});

  final int? remaining;
  final bool staff;

  @override
  State<_TutorChat> createState() => _TutorChatState();
}

class _TutorChatState extends State<_TutorChat> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Message> _messages = <_Message>[];
  int? _conversationId;
  int? _remaining;
  bool _sending = false;
  bool _opening = false;

  String get _kind => widget.staff ? 'staff' : 'tutor';

  /// Test davomidagi cheklov faqat o'quvchi ustoziga tegishli.
  int _locked(int testing) => widget.staff ? 0 : testing;

  @override
  void initState() {
    super.initState();
    _remaining = widget.remaining;
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    if (_locked(activeTestPages.value) > 0) {
      showMessage(context, tr("Test davomida AI ustoz ishlamaydi. Testni yakunlagach savol bering."), error: true);
      return;
    }
    setState(() {
      _messages.add(_Message('user', text));
      _sending = true;
      _input.clear();
    });
    _toEnd();
    try {
      final data = asMap(await AppScope.read(context).api.post('ai/chat', <String, Object?>{
        'kind': _kind,
        'message': text,
        'conversation_id': _conversationId,
        'locale': I18n.locale,
      }));
      if (!mounted) return;
      setState(() {
        _conversationId = asInt(data['conversation_id']);
        _remaining = data['remaining'] == null ? null : asInt(data['remaining']);
        _messages.add(_Message('assistant', asText(data['reply'])));
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        // Yuborilmagan savol matni qaytariladi — qayta yuborish oson bo'lsin.
        _messages.removeLast();
        _input.text = text;
        _messages.add(_Message('assistant', error.message, failed: true));
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _toEnd();
    }
  }

  void _newChat() {
    setState(() {
      _messages.clear();
      _conversationId = null;
    });
  }

  Future<void> _history() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => FractionallySizedBox(heightFactor: 0.7, child: _HistorySheet(currentId: _conversationId, kind: _kind)),
    );
    if (picked == null || !mounted) return;
    if (picked == -1) {
      // Joriy suhbat o'chirildi
      _newChat();
      return;
    }
    setState(() => _opening = true);
    try {
      final data = asMap(await AppScope.read(context).api.get('ai/conversations/$picked'));
      if (!mounted) return;
      setState(() {
        _conversationId = asInt(data['id']);
        _messages
          ..clear()
          ..addAll(asList(data['messages'], 'messages').map((item) => _Message(asText(item['role']), asText(item['content']))));
      });
      _toEnd();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(widget.staff ? tr('AI yordamchi') : tr('AI ustoz')),
          if (_remaining != null)
            Text(tr('Shu oy: {0} ta javob qoldi', <Object?>[_remaining]),
                style: TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w500)),
        ]),
        actions: <Widget>[
          IconButton(tooltip: tr('Suhbatlar'), onPressed: _history, icon: const Icon(Icons.history_rounded)),
          IconButton(tooltip: tr('Yangi suhbat'), onPressed: _messages.isEmpty ? null : _newChat, icon: const Icon(Icons.add_comment_outlined)),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: activeTestPages,
        builder: (context, active, _) {
          final testing = _locked(active);
          return Column(children: <Widget>[
          if (testing > 0)
            Material(
              color: AppColors.soft(AppColors.warning),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(children: <Widget>[
                  const Icon(Icons.timer_outlined, color: AppColors.warning),
                  const SizedBox(width: 10),
                  Expanded(child: Text(tr("Test davomida AI ustoz ishlamaydi. Testni yakunlagach savol bering."))),
                ]),
              ),
            ),
          if (_opening) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _messages.isEmpty
                ? _Intro(staff: widget.staff, onPick: testing > 0 ? null : _send)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _messages.length) return _Typing(staff: widget.staff);
                      return _Bubble(message: _messages[index]);
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(color: AppColors.card, border: Border(top: BorderSide(color: AppColors.line))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: testing == 0,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 4000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(hintText: tr('Savolingizni yozing...'), counterText: '', isDense: true),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  tooltip: tr('Yuborish'),
                  onPressed: _sending || testing > 0 ? null : () => _send(),
                  icon: const Icon(Icons.send_rounded),
                ),
              ]),
            ),
          ),
        ]);
        },
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onPick, this.staff = false});

  final ValueChanged<String>? onPick;
  final bool staff;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: AppColors.sun.withAlpha(46), borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.auto_awesome_rounded, color: AppColors.sun, size: 32),
          ),
        ),
        const SizedBox(height: 14),
        Text(
            staff
                ? tr("Xat, e'lon, dars rejasi yoki test savollarini tayyorlashda yordam so'rang.")
                : tr("Tushunmagan mavzuingizni so'rang. Ustoz javobni aytmaydi — o'zingiz yechishingizga yordam beradi."),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.ink, fontSize: 15)),
        const SizedBox(height: 6),
        Text(
            staff
                ? tr("Javoblarni yuborishdan oldin tekshiring: AI xato qilishi mumkin. Shaxsiy ma'lumotlarni yozmang.")
                : tr("Masalan, masalani yuboring va qayerda to'xtab qolganingizni yozing. Test ishlayotganingizda ustoz o'chadi."),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 20),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: <Widget>[
          for (final item in staff ? _staffSuggestions : _suggestions)
            // Uzun tavsiyalar kesilmasin: chip o'rniga ikki qatorgacha o'raladigan tugma.
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onPick == null ? null : () => onPick!(tr(item)),
              child: Text(tr(item), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
            ),
        ]),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final _Message message;

  @override
  Widget build(BuildContext context) {
    final mine = message.mine;
    final background = message.failed ? AppColors.soft(AppColors.danger) : (mine ? AppColors.brand : AppColors.card);
    final foreground = message.failed ? AppColors.danger : (mine ? Colors.white : AppColors.ink);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: background,
          border: mine ? null : Border.all(color: AppColors.line),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: mine
            ? SelectableText(message.content, style: TextStyle(color: foreground, fontSize: 15))
            : MathText(_plain(message.content), style: TextStyle(color: foreground, fontSize: 15, height: 1.35)),
      ),
    );
  }

  /// Javobdagi oddiy Markdown belgilari (**qalin**, # sarlavha) olib tashlanadi — formulalar ($...$) saqlanadi.
  static String _plain(String text) => text
      .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (match) => match.group(1) ?? '')
      .replaceAllMapped(RegExp(r'^#{1,6}\s*', multiLine: true), (_) => '')
      .replaceAllMapped(RegExp(r'^\s*[-*]\s+', multiLine: true), (_) => '• ');
}

class _Typing extends StatelessWidget {
  const _Typing({this.staff = false});

  final bool staff;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text(staff ? tr('Yozmoqda...') : tr('Ustoz yozmoqda...'), style: TextStyle(color: AppColors.muted)),
        ]),
      ),
    );
  }
}

/// Oldingi suhbatlar: tanlash (id) yoki o'chirish.
class _HistorySheet extends StatelessWidget {
  const _HistorySheet({required this.currentId, this.kind = 'tutor'});

  final String kind;

  /// Joriy suhbat o'chirilsa, varaq -1 bilan yopiladi (yangi suhbat boshlanadi).
  final int? currentId;

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Column(children: <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Row(children: <Widget>[
          Expanded(child: Text(tr('Suhbatlar'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ]),
      ),
      Expanded(
        child: AsyncView<List<Map<String, dynamic>>>(
          load: () async => asList(await api.get('ai/conversations', query: <String, Object?>{'kind': kind})),
          builder: (context, items, reload) {
            if (items.isEmpty) {
              return ListView(children: <Widget>[EmptyState(icon: Icons.forum_outlined, text: tr("Hali suhbat yo'q."))]);
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final item = items[index];
                final title = asText(item['title']);
                return ListTile(
                  leading: const Icon(Icons.chat_bubble_outline_rounded),
                  title: Text(title.isEmpty ? tr('Suhbat') : title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(dateTime(item['updated_at'])),
                  onTap: () => Navigator.pop(context, asInt(item['id'])),
                  trailing: IconButton(
                    tooltip: tr("O'chirish"),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (!await confirm(context, tr("Suhbat o'chirilsinmi?"), action: tr("O'chirish"), danger: true)) return;
                      try {
                        await api.delete('ai/conversations/${asInt(item['id'])}');
                        if (asInt(item['id']) == currentId) {
                          if (context.mounted) Navigator.pop(context, -1);
                          return;
                        }
                        await reload();
                      } on ApiException catch (error) {
                        if (context.mounted) showMessage(context, error.message, error: true);
                      }
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}
