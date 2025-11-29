/// User profile model matching the user_profiles table in Supabase
class UserProfile {
  final String id;
  final DateTime createdAt;
  final String? displayName;
  final String emailAddress;
  final DateTime? birthday;
  final bool mailingList;

  UserProfile({
    required this.id,
    required this.createdAt,
    this.displayName,
    required this.emailAddress,
    this.birthday,
    this.mailingList = false,
  });

  /// Create UserProfile from Supabase JSON response
  /// This is called when we fetch user data from the database
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      displayName: json['display_name'] as String?,
      emailAddress: json['email_address'] as String,
      birthday: json['Birthday'] != null
          ? DateTime.parse(json['Birthday'] as String)
          : null,
      mailingList: json['Mailing_List'] as bool? ?? false,
    );
  }

  /// Convert UserProfile to JSON for Supabase insert/update
  /// This is called when we save user data to the database
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'display_name': displayName,
      'email_address': emailAddress,
      'Birthday': birthday?.toIso8601String(),
      'Mailing_List': mailingList,
    };
  }

  /// Create a copy of UserProfile with some fields changed
  /// Useful for updating specific fields without changing others
  UserProfile copyWith({
    String? id,
    DateTime? createdAt,
    String? displayName,
    String? emailAddress,
    DateTime? birthday,
    bool? mailingList,
  }) {
    return UserProfile(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      displayName: displayName ?? this.displayName,
      emailAddress: emailAddress ?? this.emailAddress,
      birthday: birthday ?? this.birthday,
      mailingList: mailingList ?? this.mailingList,
    );
  }

  @override
  String toString() {
    return 'UserProfile(id: $id, email: $emailAddress, displayName: $displayName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserProfile && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
