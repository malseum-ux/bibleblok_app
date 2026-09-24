// 구독 판별 — "구독 중인가"는 이 파일에서만 판단한다 (워드블록 lib/plan.dart 의 isProPlan 과 같은 원칙)
// 결제(RevenueCat 등)를 붙일 때는 구독 표(subscriptions)를 채우는 쪽만 만들면 되고, 여기는 그대로 둔다.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'auth.dart';

class SubscriptionState {
  /// 바이블블록 구독 중인지
  final bool active;
  final DateTime? expiresAt;

  /// 구독 표가 아직 없으면 false (supabase/sql/001_subscriptions.sql 실행 전)
  final bool ready;

  const SubscriptionState({required this.active, this.expiresAt, this.ready = true});
  static const none = SubscriptionState(active: false);
}

final subscriptionProvider = FutureProvider<SubscriptionState>((ref) async {
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null) return SubscriptionState.none;
  try {
    final row = await Supabase.instance.client
        .from('subscriptions')
        .select('status, expires_at')
        .eq('user_id', user.id)
        .eq('app', 'bibleblok')
        .maybeSingle();
    if (row == null) return SubscriptionState.none;
    final expires = row['expires_at'] == null ? null : DateTime.tryParse('${row['expires_at']}');
    final active = row['status'] == 'active' && (expires == null || expires.isAfter(DateTime.now()));
    return SubscriptionState(active: active, expiresAt: expires);
  } catch (_) {
    return const SubscriptionState(active: false, ready: false);
  }
});

/// AI 를 쓸 수 있는지 — 구독 확인을 켜기 전(kRequireSubscription = false)에는 로그인만으로 충분하다
bool canUseAi(SubscriptionState? s) => !kRequireSubscription || (s?.active ?? false);
