import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/longevity.dart';

/// Shared by the Library bar and Explore: preset values plus "Personalizado…".
const adPresets = <int?>[null, 2, 3, 5, 10, 20];

String daysLabel(int? d, {bool long = false}) => d == null
    ? 'Qualquer idade'
    : long
    ? 'Ativos há $d+ dias'
    : '$d+ dias';

String adsLabel(int? n, {bool long = false}) => n == null
    ? (long ? 'Qualquer quantidade' : 'Qualquer qtd.')
    : long
    ? '$n+ anúncios ativos'
    : '$n+ anúncios';

class NumberFilterChip extends StatelessWidget {
  const NumberFilterChip({
    super.key,
    required this.icon,
    required this.value,
    required this.presets,
    required this.label,
    required this.menuLabel,
    required this.onChanged,
    required this.customTitle,
    required this.customSuffix,
    required this.min,
    required this.max,
    this.tooltip,
    this.compact = false,
  });
  final IconData icon;
  final int? value;
  final List<int?> presets;
  final String Function(int?) label, menuLabel;
  final ValueChanged<int?> onChanged;
  final String customTitle, customSuffix;
  final int min, max;
  final String? tooltip;
  final bool compact;

  static const _any = -1, _custom = -2;

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    tooltip: tooltip,
    initialValue: value ?? _any,
    onSelected: (v) async {
      if (v != _custom) {
        onChanged(v == _any ? null : v);
        return;
      }
      final typed = await askNumber(
        context,
        title: customTitle,
        suffix: customSuffix,
        initial: value,
        min: min,
        max: max,
      );
      if (typed != null) onChanged(typed);
    },
    itemBuilder: (_) => [
      for (final p in presets)
        PopupMenuItem(value: p ?? _any, child: Text(menuLabel(p))),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: _custom,
        child: Text(
          value != null && !presets.contains(value)
              ? 'Personalizado (${label(value)})'
              : 'Personalizado…',
        ),
      ),
    ],
    child: Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label(value)),
      visualDensity: compact ? VisualDensity.compact : null,
    ),
  );
}

/// Number between [min] and [max]; null when cancelled.
Future<int?> askNumber(
  BuildContext context, {
  required String title,
  required String suffix,
  required int min,
  required int max,
  int? initial,
}) async {
  final form = GlobalKey<FormState>();
  final input = TextEditingController(text: initial?.toString() ?? '');
  final result = await showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Form(
        key: form,
        child: TextFormField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: max.toString().length,
          decoration: InputDecoration(
            suffixText: suffix,
            helperText: 'De $min a $max',
          ),
          validator: (v) {
            final n = int.tryParse(v ?? '');
            return n == null || n < min || n > max
                ? 'Use um número de $min a $max.'
                : null;
          },
          onFieldSubmitted: (v) {
            if (form.currentState!.validate()) {
              Navigator.pop(context, int.parse(v));
            }
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(context, int.parse(input.text));
            }
          },
          child: const Text('Aplicar'),
        ),
      ],
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  input.dispose();
  return result;
}

/// Day filter used everywhere.
NumberFilterChip daysChip({
  required int? value,
  required ValueChanged<int?> onChanged,
  bool long = false,
  bool compact = false,
}) => NumberFilterChip(
  icon: Icons.schedule_rounded,
  value: value,
  presets: LongevityFilter.presets,
  label: (d) => daysLabel(d, long: long),
  menuLabel: (d) => daysLabel(d, long: true),
  onChanged: onChanged,
  customTitle: 'Ativos há pelo menos',
  customSuffix: 'dias',
  min: 0,
  max: LongevityFilter.maxDays,
  tooltip: 'Idade mínima dos anúncios',
  compact: compact,
);

/// Minimum active ads using the same creative, as Meta shows on the card.
NumberFilterChip adsChip({
  required int? value,
  required ValueChanged<int?> onChanged,
  bool long = false,
  bool compact = false,
}) => NumberFilterChip(
  icon: Icons.layers_outlined,
  value: value,
  presets: adPresets,
  label: (n) => adsLabel(n, long: long),
  menuLabel: (n) => adsLabel(n, long: true),
  onChanged: onChanged,
  customTitle: 'Mínimo de anúncios ativos com o mesmo criativo',
  customSuffix: 'anúncios',
  min: 1,
  max: 1000,
  tooltip: 'Quantidade de anúncios ativos com o mesmo criativo',
  compact: compact,
);
