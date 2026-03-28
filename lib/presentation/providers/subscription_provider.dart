import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/subscription_repository.dart';

/// Repository provider
final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return SubscriptionRepository(Supabase.instance.client);
});

/// Current user's subscription state
final subscriptionProvider = FutureProvider<Subscription>((ref) async {
  final repo = ref.watch(subscriptionRepositoryProvider);
  return repo.getSubscription();
});

/// Weekly recipe usage count
final recipeUsageCountProvider = FutureProvider<int>((ref) async {
  final repo = ref.watch(subscriptionRepositoryProvider);
  return repo.getWeeklyUsageCount();
});

/// Whether the user can generate a recipe right now
final canGenerateRecipeProvider = FutureProvider<bool>((ref) async {
  final subscription = await ref.watch(subscriptionProvider.future);
  if (subscription.isPremium || subscription.isTrialActive) return true;

  final usageCount = await ref.watch(recipeUsageCountProvider.future);
  return usageCount < SubscriptionRepository.freeWeeklyLimit;
});

/// Whether the user has premium access (paid or trial)
final isPremiumProvider = FutureProvider<bool>((ref) async {
  final subscription = await ref.watch(subscriptionProvider.future);
  return subscription.isPremium || subscription.isTrialActive;
});

/// Remaining free recipes this week
final remainingFreeRecipesProvider = FutureProvider<int>((ref) async {
  final subscription = await ref.watch(subscriptionProvider.future);
  if (subscription.isPremium || subscription.isTrialActive) return -1; // unlimited

  final usageCount = await ref.watch(recipeUsageCountProvider.future);
  final remaining = SubscriptionRepository.freeWeeklyLimit - usageCount;
  return remaining.clamp(0, SubscriptionRepository.freeWeeklyLimit);
});
