// 로그인 화면 — 웹 AuthGate.jsx 와 같은 카드 모양
// Apple · Google · 카카오 · 이메일 6자리 인증번호 (처음 한 번만, 이후 자동 로그인)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants.dart';
import '../providers/app_state.dart';
import '../providers/auth.dart';
import '../theme/app_colors.dart';
import '../widgets/ui.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  final emailCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  bool codeSent = false;
  bool loading = false;
  String? busyProvider;
  String? error;

  @override
  void dispose() {
    emailCtrl.dispose();
    codeCtrl.dispose();
    super.dispose();
  }

  String _msg(Object e) => e is AuthException ? e.message : '$e'.replaceFirst('Exception: ', '');

  Future<void> oauth(OAuthProvider p) async {
    setState(() {
      busyProvider = p.name;
      error = null;
    });
    try {
      await signInWithProvider(p);
    } catch (e) {
      if (mounted) setState(() => error = _msg(e));
    } finally {
      if (mounted) setState(() => busyProvider = null);
    }
  }

  Future<void> sendCode() async {
    if (emailCtrl.text.trim().isEmpty) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await sendEmailCode(emailCtrl.text);
      if (mounted) setState(() => codeSent = true);
    } catch (e) {
      if (mounted) setState(() => error = _msg(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> verify() async {
    if (codeCtrl.text.trim().length < 6) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await verifyEmailCode(emailCtrl.text, codeCtrl.text);
    } catch (e) {
      if (mounted) setState(() => error = _msg(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final lang = ref.watch(settingsProvider).lang;
    final ko = lang == 'ko';

    Widget providerButton(OAuthProvider p, String label, {required Color bg, required Color fg, Color? border}) {
      final busy = busyProvider == p.name;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextButton(
          onPressed: busyProvider != null ? null : () => oauth(p),
          style: TextButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            disabledForegroundColor: fg.withValues(alpha: 0.6),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7), side: BorderSide(color: border ?? bg)),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          child: Text(busy ? (ko ? '연결 중...' : 'Connecting...') : label),
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            width: 340,
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 40),
            decoration: BoxDecoration(color: c.bgSidebar, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(12)),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Align(
                alignment: Alignment.centerLeft,
                child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset('assets/icon-192.png', width: 56, height: 56)),
              ),
              const SizedBox(height: 14),
              Text(appName(lang), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.textHeading)),
              const SizedBox(height: 6),
              Text(ko ? '로그인하여 여러 기기에서 사용하세요' : 'Sign in to use it on all your devices', style: TextStyle(fontSize: 13, color: c.textMuted)),
              const SizedBox(height: 28),
              providerButton(OAuthProvider.apple, ko ? 'Apple로 로그인' : 'Sign in with Apple', bg: Colors.black, fg: Colors.white),
              providerButton(OAuthProvider.google, ko ? 'Google로 로그인' : 'Sign in with Google', bg: c.bgSidebar, fg: c.text, border: c.border),
              providerButton(OAuthProvider.kakao, ko ? '카카오로 로그인' : 'Sign in with Kakao', bg: const Color(0xFFFEE500), fg: const Color(0xD9000000)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Container(height: 1, color: c.border)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(ko ? '또는' : 'or', style: TextStyle(fontSize: 12, color: c.textMuted))),
                Expanded(child: Container(height: 1, color: c.border)),
              ]),
              const SizedBox(height: 16),
              if (!codeSent) ...[
                AppInput(controller: emailCtrl, hint: ko ? '이메일 주소' : 'Email address', onSubmitted: (_) => sendCode()),
                const SizedBox(height: 12),
                AccentButton(
                  loading ? (ko ? '전송 중...' : 'Sending...') : (ko ? '이메일 로그인 메일 받기' : 'Email me a sign-in link'),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  onPressed: loading ? null : sendCode,
                ),
              ] else ...[
                Text(
                  ko
                      ? '${emailCtrl.text.trim()} 메일함을 확인해 주세요.\n메일의 로그인 링크를 누르면 바로 로그인됩니다. 메일에 6자리 번호가 있으면 아래에 입력해도 됩니다.'
                      : 'Check ${emailCtrl.text.trim()}.\nOpen the sign-in link in the email, or enter the 6-digit code if the email has one.',
                  style: TextStyle(fontSize: 13, color: c.text, height: 1.6),
                ),
                const SizedBox(height: 10),
                AppInput(controller: codeCtrl, hint: ko ? '인증번호 6자리' : '6-digit code', autofocus: true, onSubmitted: (_) => verify()),
                const SizedBox(height: 12),
                AccentButton(
                  loading ? (ko ? '확인 중...' : 'Verifying...') : (ko ? '로그인' : 'Sign in'),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  onPressed: loading ? null : verify,
                ),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  GhostTextButton(ko ? '다른 이메일' : 'Change email', opacity: 0.8, fontSize: 12, onPressed: () => setState(() {
                        codeSent = false;
                        codeCtrl.clear();
                      })),
                  GhostTextButton(ko ? '메일 다시 받기' : 'Resend email', opacity: 0.8, fontSize: 12, onPressed: sendCode),
                ]),
              ],
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
