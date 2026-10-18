import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';

/// Til tanlash tugmasi (globus): o'zbek, rus, ingliz.
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: tr('Til'),
      initialValue: I18n.locale,
      onSelected: (code) => AppScope.read(context).setLocale(code),
      itemBuilder: (context) => I18n.codes
          .map((code) => PopupMenuItem<String>(value: code, child: Text(I18n.labels[code] ?? code)))
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const Icon(Icons.language, size: 20, color: AppColors.muted),
          const SizedBox(width: 6),
          Text(I18n.locale.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted)),
        ]),
      ),
    );
  }
}
