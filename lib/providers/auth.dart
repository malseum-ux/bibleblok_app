// 로그인 상태 — Supabase 인증 (Apple · Google · 카카오 · 이메일 6자리 인증번호)
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

SupabaseClient get _sb => Supabase.instance.client;

/// 지금 로그인한 사용자 (없으면 null) — 로그인·로그아웃할 때마다 바뀐다
final authUserProvider = StreamProvider<User?>((ref) async* {
  yield _sb.auth.currentUser;
  await for (final state in _sb.auth.onAuthStateChange) {
    yield state.session?.user;
  }
});

/// 웹은 지금 페이지로 돌아오고, 앱은 앱 주소로 돌아온다 (앱 주소는 Mac 빌드 단계에서 등록)
String? get _redirect => kIsWeb ? Uri.base.origin : 'com.blokzip.bibleblokapp://login-callback';

Future<void> signInWithProvider(OAuthProvider provider) async {
  await _sb.auth.signInWithOAuth(provider, redirectTo: _redirect);
}

/// 이메일로 로그인 메일 보내기 — 메일의 링크를 누르면 앱으로 돌아와 로그인된다
/// (메일 템플릿에 6자리 번호를 넣으려면 발송 서버(SMTP)를 연결해야 한다 — 연결 후에는 번호로도 로그인)
Future<void> sendEmailCode(String email) =>
    _sb.auth.signInWithOtp(email: email.trim(), shouldCreateUser: true, emailRedirectTo: _redirect);

/// 받은 6자리 번호로 로그인
Future<void> verifyEmailCode(String email, String code) =>
    _sb.auth.verifyOTP(email: email.trim(), token: code.trim(), type: OtpType.email);

Future<void> signOut() => _sb.auth.signOut();

/// 회원 탈퇴 — 서버에서 계정을 지운 뒤 로그아웃
Future<void> deleteAccount() async {
  final token = _sb.auth.currentSession?.accessToken;
  if (token == null) throw Exception('로그인이 필요합니다.');
  final res = await http.post(
    Uri.parse(kDeleteAccountEndpoint),
    headers: {'Authorization': 'Bearer $token', 'apikey': kSupabaseAnonKey},
  );
  if (res.statusCode != 200) throw Exception('탈퇴 처리 실패 (${res.statusCode})');
  await _sb.auth.signOut();
}

/// 로그인 방법 이름 (설정 화면 표시용)
String providerLabel(User user) {
  final p = user.appMetadata['provider'] as String? ?? 'email';
  return const {'apple': 'Apple', 'google': 'Google', 'kakao': '카카오', 'email': '이메일'}[p] ?? p;
}
