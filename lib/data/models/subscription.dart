/// Subscription model for Milk Premium
class Subscription {
  final String? id;
  final String userId;
  final String tier; // 'free' or 'premium'
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final DateTime? trialStartedAt;
  final DateTime? trialEndsAt;
  final String? platform;
  final String? storeTransactionId;

  Subscription({
    this.id,
    required this.userId,
    this.tier = 'free',
    this.startedAt,
    this.expiresAt,
    this.trialStartedAt,
    this.trialEndsAt,
    this.platform,
    this.storeTransactionId,
  });

  bool get isPremium => tier == 'premium' && !isExpired;

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  bool get isTrialActive {
    if (trialEndsAt == null) return false;
    return DateTime.now().isBefore(trialEndsAt!);
  }

  bool get hasUsedTrial => trialStartedAt != null;

  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      id: json['id'] as String?,
      userId: json['user_id'] as String,
      tier: json['tier'] as String? ?? 'free',
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      trialStartedAt: json['trial_started_at'] != null
          ? DateTime.parse(json['trial_started_at'] as String)
          : null,
      trialEndsAt: json['trial_ends_at'] != null
          ? DateTime.parse(json['trial_ends_at'] as String)
          : null,
      platform: json['platform'] as String?,
      storeTransactionId: json['store_transaction_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'tier': tier,
      if (startedAt != null) 'started_at': startedAt!.toIso8601String(),
      if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
      if (trialStartedAt != null)
        'trial_started_at': trialStartedAt!.toIso8601String(),
      if (trialEndsAt != null)
        'trial_ends_at': trialEndsAt!.toIso8601String(),
      if (platform != null) 'platform': platform,
      if (storeTransactionId != null)
        'store_transaction_id': storeTransactionId,
    };
  }

  Subscription copyWith({
    String? id,
    String? userId,
    String? tier,
    DateTime? startedAt,
    DateTime? expiresAt,
    DateTime? trialStartedAt,
    DateTime? trialEndsAt,
    String? platform,
    String? storeTransactionId,
  }) {
    return Subscription(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      tier: tier ?? this.tier,
      startedAt: startedAt ?? this.startedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      trialStartedAt: trialStartedAt ?? this.trialStartedAt,
      trialEndsAt: trialEndsAt ?? this.trialEndsAt,
      platform: platform ?? this.platform,
      storeTransactionId: storeTransactionId ?? this.storeTransactionId,
    );
  }

  /// Free tier default for users without a subscription record
  factory Subscription.free(String userId) {
    return Subscription(userId: userId, tier: 'free');
  }
}
