import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/subscription.dart';

/// Repository for subscription and recipe usage tracking
class SubscriptionRepository {
  final SupabaseClient _supabase;

  /// Free tier weekly recipe limit
  static const int freeWeeklyLimit = 3;

  /// Trial duration in days
  static const int trialDurationDays = 7;

  SubscriptionRepository(this._supabase);

  /// Get the current user's subscription, or a free-tier default
  Future<Subscription> getSubscription() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return Subscription.free('');

      final response = await _supabase
          .from('user_subscriptions')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) {
        return Subscription.free(userId);
      }

      return Subscription.fromJson(response);
    } catch (e) {
      debugPrint('Error fetching subscription: $e');
      // Default to free tier on error — don't block the user
      final userId = _supabase.auth.currentUser?.id ?? '';
      return Subscription.free(userId);
    }
  }

  /// Count recipes generated this week (Monday 00:00 SAST to now)
  Future<int> getWeeklyUsageCount() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return 0;

      final now = DateTime.now().toUtc();
      // Find the most recent Monday at 00:00 SAST (UTC+2)
      final nowSast = now.add(const Duration(hours: 2));
      final daysSinceMonday = (nowSast.weekday - 1) % 7;
      final mondaySast = DateTime(
        nowSast.year,
        nowSast.month,
        nowSast.day - daysSinceMonday,
      );
      // Convert back to UTC for the query
      final mondayUtc = mondaySast.subtract(const Duration(hours: 2));

      final response = await _supabase
          .from('recipe_usage')
          .select('id')
          .eq('user_id', userId)
          .gte('generated_at', mondayUtc.toIso8601String());

      return (response as List).length;
    } catch (e) {
      debugPrint('Error fetching weekly usage: $e');
      return 0;
    }
  }

  /// Record a recipe generation
  Future<void> recordRecipeGeneration(String recipeName) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _supabase.from('recipe_usage').insert({
        'user_id': userId,
        'recipe_name': recipeName,
      });
    } catch (e) {
      debugPrint('Error recording recipe usage: $e');
      // Don't throw — usage tracking failure shouldn't block generation
    }
  }

  /// Check if the user can generate a recipe (premium or under free limit)
  Future<bool> canGenerateRecipe() async {
    final subscription = await getSubscription();

    // Premium users or active trial users have unlimited access
    if (subscription.isPremium || subscription.isTrialActive) {
      return true;
    }

    // Free users: check weekly limit
    final weeklyCount = await getWeeklyUsageCount();
    return weeklyCount < freeWeeklyLimit;
  }

  /// Start a free trial for the current user
  Future<Subscription> startFreeTrial() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    final now = DateTime.now().toUtc();
    final trialEnd = now.add(const Duration(days: trialDurationDays));

    final data = {
      'user_id': userId,
      'tier': 'premium',
      'started_at': now.toIso8601String(),
      'trial_started_at': now.toIso8601String(),
      'trial_ends_at': trialEnd.toIso8601String(),
      'expires_at': trialEnd.toIso8601String(),
    };

    final response = await _supabase
        .from('user_subscriptions')
        .upsert(data, onConflict: 'user_id')
        .select()
        .single();

    return Subscription.fromJson(response);
  }

  /// Activate a premium subscription (called after successful payment)
  Future<Subscription> activatePremium({
    required String platform,
    required String transactionId,
    required DateTime expiresAt,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    final data = {
      'user_id': userId,
      'tier': 'premium',
      'started_at': DateTime.now().toUtc().toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'platform': platform,
      'store_transaction_id': transactionId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    final response = await _supabase
        .from('user_subscriptions')
        .upsert(data, onConflict: 'user_id')
        .select()
        .single();

    return Subscription.fromJson(response);
  }
}
