class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.username,
    required this.role,
  });

  final String id;
  final String email;
  final String username;
  final String role;

  bool get isAdmin => role == 'admin';

  factory AppUser.from({
    required String id,
    required String email,
    Map<String, dynamic>? profile,
  }) =>
      AppUser(
        id: id,
        email: email,
        username: (profile?['username'] as String?)?.trim().isNotEmpty == true
            ? profile!['username'] as String
            : (email.contains('@') ? email.split('@').first : email),
        role: (profile?['role'] as String?) ?? 'user',
      );
}
