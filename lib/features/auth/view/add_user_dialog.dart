import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../service/auth_service.dart';

/// Admin-only form to create a new account (name, email, password, role).
class AddUserDialog extends ConsumerStatefulWidget {
  const AddUserDialog({super.key});

  @override
  ConsumerState<AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends ConsumerState<AddUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _role = 'user';
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).createUser(
            fullName: _name.text,
            email: _email.text,
            password: _password.text,
            role: _role,
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إنشاء حساب "${_name.text.trim()}" بنجاح')),
        );
      }
    } on AuthException catch (e) {
      setState(() => _error = _translate(e.message));
    } catch (e) {
      setState(() => _error = 'تعذّر إنشاء الحساب: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _translate(String message) {
    final m = message.toLowerCase();
    if (m.contains('already registered') || m.contains('already been registered')) {
      return 'هذا البريد مسجّل مسبقًا.';
    }
    if (m.contains('password')) return 'كلمة المرور ضعيفة (٦ أحرف على الأقل).';
    return message;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة مستخدم جديد'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'الاسم الثلاثي', prefixIcon: Icon(Icons.badge_outlined)),
                validator: (v) {
                  final words = (v ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
                  if (words.length < 3) return 'أدخل الاسم الثلاثي (ثلاث كلمات)';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.mail_outline)),
                validator: (v) => (v ?? '').contains('@') ? null : 'بريد إلكتروني غير صحيح',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => (v ?? '').length < 6 ? '٦ أحرف على الأقل' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'الدور', prefixIcon: Icon(Icons.shield_outlined)),
                items: const [
                  DropdownMenuItem(value: 'user', child: Text('مستخدم')),
                  DropdownMenuItem(value: 'admin', child: Text('مشرف (admin)')),
                ],
                onChanged: (v) => setState(() => _role = v ?? 'user'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('إنشاء'),
        ),
      ],
    );
  }
}
