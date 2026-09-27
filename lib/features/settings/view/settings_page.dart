import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/backup/cloud_backup_service.dart';
import '../../auth/service/auth_service.dart';
import '../../auth/view/add_user_dialog.dart';
import '../../documents/view/bulk_rescan_page.dart';
import '../controller/theme_controller.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  Future<Uint8List?> _buildWithProgress(BuildContext context, WidgetRef ref) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 16),
                Text('جارٍ تجهيز النسخة من السحابة…'),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      return await ref.read(cloudBackupServiceProvider).build();
    } catch (_) {
      return null;
    } finally {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final bytes = await _buildWithProgress(context, ref);
    if (bytes == null) {
      messenger.showSnackBar(const SnackBar(content: Text('تعذّر تجهيز النسخة. تحقّق من الاتصال.')));
      return;
    }
    final name = ref.read(cloudBackupServiceProvider).defaultFileName();
    try {
      if (_isMobile) {
        final tmp = await getTemporaryDirectory();
        final path = p.join(tmp.path, name);
        await File(path).writeAsBytes(bytes);
        await SharePlus.instance.share(
          ShareParams(files: [XFile(path)], text: 'نسخة احتياطية كاملة - ديوان الفرقة 42'),
        );
      } else {
        final location = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: const [XTypeGroup(label: 'ZIP', extensions: ['zip'])],
        );
        if (location == null) return;
        await File(location.path).writeAsBytes(bytes);
        messenger.showSnackBar(SnackBar(content: Text('تم حفظ النسخة الكاملة:\n${location.path}')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final isAdmin = user?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _sectionTitle(context, 'الحساب'),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: const Icon(Icons.person_outline, color: Colors.white),
              ),
              title: Text(user?.username ?? '—', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(user?.email ?? 'غير مسجّل'),
              trailing: TextButton.icon(
                onPressed: () => ref.read(authServiceProvider).signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('خروج'),
              ),
            ),
          ),
          if (isAdmin) ...[
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () => showDialog(context: context, builder: (_) => const AddUserDialog()),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('إضافة مستخدم جديد'),
            ),
          ],
          const SizedBox(height: 20),
          _sectionTitle(context, 'المظهر'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('فاتح')),
                  ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('داكن')),
                  ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('النظام')),
                ],
                selected: {mode},
                onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).setMode(s.first),
              ),
            ),
          ),
          if (isAdmin) ...[
            const SizedBox(height: 20),
            _sectionTitle(context, 'النسخ الاحتياطي'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('نسخة كاملة من السحابة: كل الطلبات والمهمات (Excel) مع جميع الصور في ملف واحد.'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _backup(context, ref),
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('إنشاء نسخة كاملة'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _sectionTitle(context, 'الصور'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'معالجة صور الطلبات القديمة دفعة واحدة: اقتصاص حواف الورقة وتحسين الوضوح، '
                      'ثم استبدال الصورة الأصلية.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const BulkRescanPage()),
                      ),
                      icon: const Icon(Icons.document_scanner_outlined),
                      label: const Text('معالجة الصور القديمة'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, right: 4),
        child: Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      );
}
