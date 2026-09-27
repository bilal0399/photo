import 'package:flutter/material.dart';

enum SortField { date, number }

class SortState {
  const SortState(this.field, {this.ascending = false});

  final SortField field;
  final bool ascending;

  SortState withField(SortField f) => SortState(f, ascending: ascending);
  SortState toggleDirection() => SortState(field, ascending: !ascending);
}

/// A compact "sort by date / number" control with an ascending/descending
/// toggle. Used at the top of the documents and tasks lists.
class SortBar extends StatelessWidget {
  const SortBar({
    super.key,
    required this.state,
    required this.onFieldChanged,
    required this.onToggleDirection,
  });

  final SortState state;
  final ValueChanged<SortField> onFieldChanged;
  final VoidCallback onToggleDirection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Row(
        children: [
          Text('ترتيب حسب:',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
          const SizedBox(width: 10),
          ChoiceChip(
            label: const Text('التاريخ'),
            selected: state.field == SortField.date,
            onSelected: (_) => onFieldChanged(SortField.date),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('الرقم'),
            selected: state.field == SortField.number,
            onSelected: (_) => onFieldChanged(SortField.number),
          ),
          const Spacer(),
          IconButton(
            tooltip: state.ascending ? 'تصاعدي' : 'تنازلي',
            onPressed: onToggleDirection,
            icon: Icon(state.ascending ? Icons.arrow_upward : Icons.arrow_downward),
          ),
        ],
      ),
    );
  }
}

int _byNumber(String a, String b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0);

/// Sorts a copy of [items] by the chosen field/direction.
List<T> applySort<T>(
  List<T> items,
  SortState sort, {
  required String Function(T) numberOf,
  required String Function(T) dateOf,
}) {
  final list = [...items];
  list.sort((a, b) {
    final r = sort.field == SortField.number
        ? _byNumber(numberOf(a), numberOf(b))
        : dateOf(a).compareTo(dateOf(b));
    return sort.ascending ? r : -r;
  });
  return list;
}
