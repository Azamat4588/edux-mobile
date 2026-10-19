// Bir nechta tashkilotda ishlaydigan foydalanuvchi: qaysi biriga kirishni tanlaydi.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

String roleLabel(String role) {
  const labels = <String, String>{
    'director': 'Direktor',
    'admin': 'Administrator',
    'teacher': "O'qituvchi",
    'student': "O'quvchi",
    'guardian': 'Ota-ona',
    'cashier': 'Kassir',
    'marketer': 'Marketolog',
  };
  return tr(labels[role] ?? role);
}

class OrganizationPicker extends StatefulWidget {
  const OrganizationPicker({super.key, this.inline = false});

  /// Sozlamalardan ochilganda (orqaga qaytish tugmasi bilan).
  final bool inline;

  @override
  State<OrganizationPicker> createState() => _OrganizationPickerState();
}

class _OrganizationPickerState extends State<OrganizationPicker> {
  int? _busy;

  Future<void> _choose(Membership membership) async {
    setState(() => _busy = membership.organizationId);
    try {
      await AppScope.read(context).selectOrganization(membership.organizationId);
      if (mounted && widget.inline) Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Tashkilotni tanlang')),
        automaticallyImplyLeading: widget.inline,
        actions: <Widget>[
          if (!widget.inline) TextButton(onPressed: session.signOut, child: Text(tr('Chiqish'))),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: session.memberships.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = session.memberships[index];
          final current = item.organizationId == session.organizationId;
          return AppCard(
            onTap: _busy == null ? () => _choose(item) : null,
            child: Row(children: <Widget>[
              Avatar(item.organization),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(item.organization, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(roleLabel(item.role), style: TextStyle(color: AppColors.muted)),
                ]),
              ),
              if (_busy == item.organizationId)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              else if (current)
                Icon(Icons.check_circle, color: AppColors.brand)
              else
                Icon(Icons.chevron_right, color: AppColors.muted),
            ]),
          );
        },
      ),
    );
  }
}
