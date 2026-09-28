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
  _FakeDocuments([this.existing = const []]);

  final List<Document> existing;
  final saved = <DocumentDraft>[];
  DocumentDraft? get created => saved.isEmpty ? null : saved.last;

  @override
  Future<List<Document>> all() async => [
        ...existing,
        for (final d in saved)
          Document(
            documentCode: '',
            bookNumber: d.bookNumber,
            datetime: d.datetime,
            bookType: d.bookType,
            requester: d.requester,
            status: d.status,
            direction: d.direction,
            summary: d.summary,
            attachmentPath: '',
            approvalDate: '',
            createdAt: '',
          ),
      ];

  @override
  Future<void> create(DocumentDraft draft, {String? sourceAttachmentPath}) async {
    saved.add(draft);
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

/// The editable text field inside the searchable lookup labelled [label].
Finder _lookupField(String label) => find.descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(DropdownMenu<String>)),
      matching: find.byType(TextField),
    );

Future<void> _selectLookup(WidgetTester tester, String label, String value) async {
  await tester.tap(_lookupField(label));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, value).last);
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester, String label) => tester
    .widget<EditableText>(
        find.descendant(of: find.widgetWithText(TextFormField, label), matching: find.byType(EditableText)))
    .controller
    .text;

String _lookupText(WidgetTester tester, String label) =>
    tester.widget<TextField>(_lookupField(label)).controller!.text;

/// Fills everything a new document needs besides the date.
Future<void> _fillRequired(WidgetTester tester, {String summary = 'نص'}) async {
  await _selectLookup(tester, 'نوع الكتاب', 'كتاب رسمي');
  await _selectLookup(tester, 'الجهة المستقبلة', kDefaultRecipients.first);
  await tester.enterText(find.widgetWithText(TextFormField, 'ملخص الكتاب'), summary);
}

void main() {
  testWidgets('outgoing books ask for the receiving party', (tester) async {
    await _openForm(tester, _FakeDocuments());

    expect(find.text('الجهة المستقبلة'), findsOneWidget);
    expect(find.text('الجهة المقدمة'), findsNothing);

    // Falls back to the built-in recipients while the server list is empty.
    await tester.tap(_lookupField('الجهة المستقبلة'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(MenuItemButton, kDefaultRecipients.first), findsOneWidget);
  });

  testWidgets('a new document starts with the lookups empty so typing searches', (tester) async {
    final docs = _FakeDocuments();
    await _openForm(tester, docs);

    expect(_lookupText(tester, 'نوع الكتاب'), isEmpty);
    expect(_lookupText(tester, 'الجهة المستقبلة'), isEmpty);

    // Nothing is picked silently: saving asks for both.
    await tester.enterText(find.widgetWithText(TextFormField, 'ملخص الكتاب'), 'نص');
    await tester.tap(find.text('حفظ الطلب'));
    await tester.pumpAndSettle();
    expect(find.text('يرجى اختيار نوع الكتاب والجهة المستقبلة'), findsOneWidget);
    expect(docs.created, isNull);
  });

  testWidgets('switching to incoming swaps the party list', (tester) async {
    await _openForm(tester, _FakeDocuments());
    await _selectLookup(tester, 'الجهة المستقبلة', kDefaultRecipients.first);

    await _pickOption(tester, kOutgoing, kIncoming);

    expect(find.text('الجهة المقدمة'), findsOneWidget);
    expect(find.text('الجهة المستقبلة'), findsNothing);
    // A recipient is not a valid sender, so the selection is cleared.
    expect(_lookupText(tester, 'الجهة المقدمة'), isEmpty);
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
    await _fillRequired(tester);
    await tester.tap(find.text('حفظ الطلب'));
    await tester.pumpAndSettle();

    expect(docs.created?.datetime, '2027-02-05');
    expect(docs.created?.bookType, 'كتاب رسمي');
    expect(docs.created?.requester, kDefaultRecipients.first);
  });

  testWidgets('save and add another keeps the batch fields and moves the number on',
      (tester) async {
    final docs = _FakeDocuments();
    await _openForm(tester, docs);
    await _fillRequired(tester, summary: 'الأول');

    await tester.tap(find.text('حفظ وإضافة طلب آخر'));
    await tester.pumpAndSettle();

    expect(docs.saved, hasLength(1));
    expect(docs.saved.single.bookNumber, '1');
    // Still on the form, ready for the next document.
    expect(find.text('إضافة طلب جديد'), findsOneWidget);
    expect(_fieldText(tester, 'ملخص الكتاب'), isEmpty);
    expect(_fieldText(tester, 'رقم الكتاب'), '2');
    expect(_lookupText(tester, 'نوع الكتاب'), 'كتاب رسمي');
    expect(_lookupText(tester, 'الجهة المستقبلة'), kDefaultRecipients.first);

    await tester.enterText(find.widgetWithText(TextFormField, 'ملخص الكتاب'), 'الثاني');
    await tester.tap(find.text('حفظ الطلب'));
    await tester.pumpAndSettle();
    expect(docs.saved.map((d) => d.bookNumber), ['1', '2']);
  });

  testWidgets('a book number already used that year asks before saving', (tester) async {
    final year = DateTime.now().year;
    final docs = _FakeDocuments([
      Document(
        id: 'x',
        documentCode: 'D',
        bookNumber: '7',
        datetime: '$year-01-10',
        bookType: 'كتاب رسمي',
        requester: 'جهة أ',
        status: 'قيد المراجعة',
        direction: kOutgoing,
        summary: 'كتاب سابق',
        attachmentPath: '',
        approvalDate: '',
        createdAt: '',
      ),
    ]);
    await _openForm(tester, docs);
    await tester.enterText(find.widgetWithText(TextFormField, 'رقم الكتاب'), '7');
    await _fillRequired(tester);

    await tester.tap(find.text('حفظ الطلب'));
    await tester.pumpAndSettle();
    expect(find.text('رقم مكرر'), findsOneWidget);

    await tester.tap(find.text('رجوع'));
    await tester.pumpAndSettle();
    expect(docs.created, isNull);

    await tester.tap(find.text('حفظ الطلب'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
    await tester.pumpAndSettle();
    expect(docs.created?.bookNumber, '7');
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
