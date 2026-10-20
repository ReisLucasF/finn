import 'package:finan/app/app_scope.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/enums/category_type.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:finan/presentation/shared/feedback_widgets.dart';
import 'package:flutter/material.dart';

const _palette = <String>[
  '1F6B4A',
  '2E7D6F',
  '3E4C7A',
  '6A4C7A',
  '7A342C',
  '8A4B2F',
  '2F5E6E',
  '5C5346',
];

class CategoryFormScreen extends StatefulWidget {
  const CategoryFormScreen({this.category, super.key});

  final Category? category;

  @override
  State<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends State<CategoryFormScreen> {
  late final TextEditingController _name = TextEditingController(
    text: widget.category?.name ?? '',
  );
  late CategoryType _type = widget.category?.type ?? CategoryType.expense;
  late bool _active = widget.category?.isActive ?? true;
  late String _color = widget.category?.color ?? _palette.first;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final scope = AppScope.of(context);
      final category = widget.category;
      if (category == null) {
        await scope.graph.createCategory(
          userId: scope.session.user.id,
          name: _name.text,
          type: _type,
          icon: 'label',
          color: _color,
        );
      } else {
        await scope.graph.updateCategory(
          id: category.id,
          name: _name.text,
          type: _type,
          isActive: _active,
          icon: category.icon,
          color: _color,
        );
      }
      if (!mounted) return;
      showSuccess(
        context,
        category == null ? 'Categoria criada' : 'Categoria atualizada',
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.category != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Editar categoria' : 'Nova categoria'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          TextField(
            controller: _name,
            autofocus: !editing,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nome'),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<CategoryType>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: [
              for (final type in CategoryType.values)
                DropdownMenuItem(value: type, child: Text(type.label)),
            ],
            onChanged: _saving
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _type = value);
                  },
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Cor', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final color in _palette)
                Semantics(
                  button: true,
                  selected: _color == color,
                  label: 'Cor $color',
                  child: InkWell(
                    onTap: _saving
                        ? null
                        : () => setState(() => _color = color),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colorFromHex(color, Colors.grey),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == color
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (editing)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Categoria ativa'),
              value: _active,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _active = value),
            ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Salvando...' : 'Salvar'),
          ),
        ],
      ),
    );
  }
}
