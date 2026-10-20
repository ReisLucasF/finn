import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/core/theme/theme_controller.dart';
import 'package:flutter/material.dart';

class ThemeModePicker extends StatefulWidget {
  const ThemeModePicker({super.key});

  @override
  State<ThemeModePicker> createState() => _ThemeModePickerState();
}

class _ThemeModePickerState extends State<ThemeModePicker> {
  ThemeMode? _draft;
  bool _edited = false;

  static const _options = <(ThemeMode, String)>[
    (ThemeMode.system, 'Sistema'),
    (ThemeMode.light, 'Claro'),
    (ThemeMode.dark, 'Escuro'),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_edited) _draft = ThemeScope.of(context).mode;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final draft = _draft ?? theme.mode;
    final changed = draft != theme.mode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<ThemeMode>(
          key: ValueKey(draft),
          initialValue: draft,
          items: [
            for (final option in _options)
              DropdownMenuItem(value: option.$1, child: Text(option.$2)),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _edited = true;
              _draft = value;
            });
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton(
          onPressed: changed ? () => theme.setMode(draft) : null,
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}
