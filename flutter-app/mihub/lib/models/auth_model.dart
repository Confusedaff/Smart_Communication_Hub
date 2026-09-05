class AuthUser {
  final String id;
  final String email;
  final String? displayName;

  AuthUser({required this.id, required this.email, this.displayName});

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String?,
    );
  }
}
