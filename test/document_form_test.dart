import 'package:diwan_archive/features/documents/model/document.dart';
import 'package:diwan_archive/features/documents/service/documents_service.dart';
import 'package:diwan_archive/features/documents/view/document_form_page.dart';
import 'package:diwan_archive/features/options/model/option_item.dart';
import 'package:diwan_archive/features/options/service/options_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeOptions implements OptionsService {
  @override
  Future<List<OptionItem>> byCategory(String category) async {
    final values = switch (category) {
      'book_type' => ['كتاب رسمي'],
      'requester' => ['جهة أ', 'جهة ب'],
      'status' => ['قيد المراجعة', 'تمت الموافقة'],
      // The server has no recipient list yet, so the built-in one is used.
      _ => <String>[],
    };
    return [for (final v in values) OptionItem(category: category, value: v, createdAt: '')];
  }
}

class _FakeDocuments implements DocumentsService {
  DocumentDraft? created;

  @override
  Future<List<Document>> all() async => const [];

  @override
  Future<void> create(DocumentDraft draft, {String? sourceAttachmentPath}) async {
    created = draft;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Opens the form on a pushed route, so saving can pop without emptying the
/// navigator.
Future<void> _openForm(WidgetTester tester, _FakeDocuments docs) async {
  // A tall window so the whole form and the open menus stay hittable.
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        optionsServiceProvider.overrideWithValue(_FakeOptions()),
        documentsServiceProvider.overrideWithValue(docs),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const DocumentFormPage())),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _pickOption(WidgetTester tester, String current, String next) async {
  await tester.tap(find.text(current).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(next).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('outgoing books ask for the receiving party', (tester) async {
    await _openForm(tester, _FakeDocuments());

    expect(find.text('الجهة المستقبلة'), findsOneWidget);
    expect(find.text('الجهة المقدمة'), findsNothing);
    // Falls back to the built-in recipients while the server list is empty.
    expect(find.text(kDefaultRecipients.first), findsOneWidget);
  });

  testWidgets('switching to incoming swaps the party list', (tester) async {
    await _openForm(tester, _FakeDocuments());

    await _pickOption(tester, kOutgoing, kIncoming);

    expect(find.text('الجهة المقدمة'), findsOneWidget);
    expect(find.text('الجهة المستقبلة'), findsNothing);
    // The recipient selection is replaced by the first sender, not kept.
    expect(find.text('جهة أ'), findsOneWidget);
    expect(find.text(kDefaultRecipients.first), findsNothing);
  });

  testWidgets('the date is three fields, not a calendar', (tester) async {
    await _openForm(tester, _FakeDocuments());

    expect(find.text('السنة'), findsOneWidget);
    expect(find.text('الشهر'), findsOneWidget);
    expect(find.text('اليوم'), findsOneWidget);
    expect(find.text('التاريخ'), findsNothing);

    final now = DateTime.now();
    expect(find.text('${now.year}'), findsOneWidget);
    expect(find.text('${now.month}'), findsOneWidget);
  });

  testWidgets('the typed day is checked against the selected month', (tester) async {
    final docs = _FakeDocuments();
    await _openForm(tester, docs);

    // February 2027 has 28 days.
    await _pickOption(tester, '${DateTime.now().year}', '2027');
    await _pickOption(tester, '${DateTime.now().month}', '2');
    await tester.enterText(find.widgetWithText(TextFormField, 'اليوم'), '30');
    await tester.enterText(find.widgetWithText(TextFormField, 'ملخص الكتاب'), 'نص');
    await tester.tap(find.text('حفظ الطلب'));
    await tester.pumpAndSettle();

    expect(find.text('من 1 إلى 28'), findsOneWidget);
    expect(docs.created, isNull);
  });

  testWidgets('year, month and day are saved as one date', (tester) async {
    final docs = _FakeDocuments();
    await _openForm(tester, docs);

    await _pickOption(tester, '${DateTime.now().year}', '2027');
    await _pickOption(tester, '${DateTime.now().month}', '2');
    await tester.enterText(find.widgetWithText(TextFormField, 'اليوم'), '5');
    await tester.enterText(find.widgetWithText(TextFormField, 'ملخص الكتاب'), 'نص');
    await tester.tap(find.text('حفظ الطلب'));
    await tester.pumpAndSettle();

    expect(docs.created?.datetime, '2027-02-05');
  });

  testWidgets('typing in a lookup field narrows the menu', (tester) async {
    await _openForm(tester, _FakeDocuments());

    // The status field takes typing instead of only opening a list.
    final status = find.ancestor(
      of: find.text('حالة الكتاب'),
      matching: find.byType(DropdownMenu<String>),
    );
    expect(status, findsOneWidget);

    await tester.tap(find.descendant(of: status, matching: find.byType(TextField)));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: status, matching: find.byType(TextField)), 'تمت');
    await tester.pumpAndSettle();

    // Only the matching entry is left in the open menu.
    expect(find.widgetWithText(MenuItemButton, 'تمت الموافقة'), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, 'قيد المراجعة'), findsNothing);
  });
}
