// «O'z telefonimdan» SMS — navbat rejimi (backend 1.36): kutilayotgan SMS'lar ro'yxati, har biri uchun telefonning SMS
// ilovasi `sms:` havolasi bilan ochiladi, keyin «Yuborildi» yoki «O'tkazib yuborish» — keyingisiga o'tadi.
// API: GET crm/sms/device, POST crm/sms/device/{id}/sent, POST crm/sms/device/{id}/skip.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/device_sms.dart';
import '../../core/format.dart';
import '../../core/help_links.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class DeviceSmsPage extends StatefulWidget {
  const DeviceSmsPage({super.key});

  @override
  State<DeviceSmsPage> createState() => _DeviceSmsPageState();
}

class _DeviceSmsPageState extends State<DeviceSmsPage> {
  List<Map<String, dynamic>>? _messages;
  int _total = 0;
  int _index = 0;
  int _sent = 0;
  bool _busy = false;
  bool _opened = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = asMap(await AppScope.read(context).api.get('crm/sms/device'));
      if (!mounted) return;
      setState(() {
        _messages = asList(data['messages'], 'messages');
        _total = asInt(data['count'], _messages!.length);
        _index = 0;
        _opened = false;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _open(Map<String, dynamic> message) async {
    final uri = Uri.parse(deviceSmsLinkOf(message, ios: Platform.isIOS));
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      showMessage(context, tr("SMS ilovasini ochib bo'lmadi."), error: true);
      return;
    }
    if (mounted) setState(() => _opened = true);
  }

  Future<void> _mark(Map<String, dynamic> message, bool sent) async {
    setState(() => _busy = true);
    try {
      final data = asMap(await AppScope.read(context).api.post('crm/sms/device/${asInt(message['id'])}/${sent ? 'sent' : 'skip'}'));
      if (!mounted) return;
      setState(() {
        if (sent) _sent++;
        _total = asInt(data['pending'], _total - 1);
        _messages!.removeAt(_index);
        if (_index >= _messages!.length) _index = 0;
        _opened = false;
      });
      if (_messages!.isEmpty && _total > 0) await _load();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
      // Boshqa xodim belgilagan bo'lishi mumkin — ro'yxat yangilansin.
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = _messages;
    return Scaffold(
      appBar: pageBar(context,
        title: Text(tr("O'z telefonimdan SMS")),
        actions: <Widget>[IconButton(tooltip: tr('Yangilash'), onPressed: _load, icon: const Icon(Icons.refresh)), const HelpButton(HelpLinks.deviceSms)],
      ),
      body: _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : messages == null
              ? const SkeletonList(count: 3)
              : messages.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(children: <Widget>[
                        EmptyState(
                          icon: Icons.mark_chat_read_outlined,
                          text: _sent > 0
                              ? tr('Hammasi yuborildi: {0} ta SMS.', <Object?>[_sent])
                              : tr("Kutilayotgan SMS yo'q. Vebda «SMS yuborish» oynasida «O'z telefonimdan» tanlansa, xabarlar shu yerga tushadi."),
                        ),
                      ]),
                    )
                  : _queue(messages),
    );
  }

  Widget _queue(List<Map<String, dynamic>> messages) {
    final message = messages[_index];
    final name = asText(message['name']);
    return ListView(padding: const EdgeInsets.all(16), children: <Widget>[
      Row(children: <Widget>[
        Expanded(child: Text(tr('Kutilmoqda: {0}', <Object?>[_total]), style: AppTheme.title(size: 18))),
        if (_sent > 0) Pill(tr('Yuborildi: {0}', <Object?>[_sent]), color: AppColors.success),
      ]),
      const SizedBox(height: 4),
      Text(tr('SMS ilovasi ochiladi — «Yuborish» ni bosing, keyin shu yerga qaytib «Yuborildi» ni belgilang.'), style: TextStyle(color: AppColors.muted)),
      const SizedBox(height: 14),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Expanded(child: Text(name.isNotEmpty ? name : asText(message['phone']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
            if (message['auto'] == true) Pill(tr('Avtomatik'), color: AppColors.muted),
          ]),
          if (name.isNotEmpty) Text(asText(message['phone']), style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(AppRadius.control)),
            child: Text(asText(message['body'])),
          ),
          const SizedBox(height: 6),
          Text(
            <String>[
              if (asInt(message['parts']) > 1) tr('{0} qism', <Object?>[asInt(message['parts'])]),
              dateTime(message['created_at']),
            ].join(', '),
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : () => _open(message),
              icon: const Icon(Icons.sms_outlined),
              label: Text(tr('SMS ilovasini ochish')),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: <Widget>[
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _mark(message, true),
                style: _opened ? FilledButton.styleFrom(backgroundColor: AppColors.soft(AppColors.success)) : null,
                icon: const Icon(Icons.check),
                label: Text(tr('Yuborildi')),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _busy ? null : () => _mark(message, false), child: Text(tr("O'tkazib yuborish"))),
          ]),
        ]),
      ),
      if (messages.length > 1) ...<Widget>[
        SectionTitle(tr('Navbatdagilar')),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(children: <Widget>[
            for (var i = 0; i < messages.length && i < 30; i++)
              if (i != _index)
                ListTile(
                  dense: true,
                  title: Text(asText(messages[i]['name'], asText(messages[i]['phone']))),
                  subtitle: Text(asText(messages[i]['body']), maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => setState(() {
                    _index = i;
                    _opened = false;
                  }),
                ),
          ]),
        ),
      ],
    ]);
  }
}
