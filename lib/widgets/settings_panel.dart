// 설정 — 웹 SettingsPanel.jsx 와 같은 배치 (오른쪽에서 열리는 260px 패널)
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants.dart';
import '../providers/app_state.dart';
import '../providers/auth.dart';
import '../providers/plan.dart';
import '../services/file_io.dart';
import '../services/fs/data_fs.dart';
import '../services/update_check.dart';
import '../services/web_import.dart';
import '../services/wordblok_sermons.dart';
import '../theme/app_colors.dart';
import 'ui.dart';

class SettingsPanel extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  /// 켤 때 확인해 둔 업데이트 결과 (있으면 바로 보여 준다)
  final UpdateInfo? initialUpdate;

  /// 성경나침반 내설교 폴더를 바꾸거나 새로고침했을 때 (사이드 목록 다시 읽기)
  final VoidCallback? onWordblokChanged;
  const SettingsPanel({super.key, required this.onClose, this.initialUpdate, this.onWordblokChanged});

  @override
  ConsumerState<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends ConsumerState<SettingsPanel> {
  String? exportStatus;
  String? importStatus; // reading | done:n | error:메시지
  String? webStatus; // reading | done:n | error:메시지
  String? version; // 지금 앱 버전
  String? updateStatus; // checking | latest | available | error
  UpdateInfo? update;

  @override
  void initState() {
    super.initState();
    if (widget.initialUpdate?.hasUpdate == true) {
      update = widget.initialUpdate;
      updateStatus = 'available';
    }
    appVersion().then((v) {
      if (mounted) setState(() => version = v);
    }).catchError((_) {});
  }

  Future<void> handleCheckUpdate() async {
    setState(() => updateStatus = 'checking');
    try {
      final info = await checkForUpdate();
      if (!mounted) return;
      setState(() {
        update = info;
        version = info.current;
        updateStatus = info.hasUpdate ? 'available' : 'latest';
      });
    } catch (_) {
      if (mounted) setState(() => updateStatus = 'error');
    }
  }

  /// 웹 바이블블록(Supabase)에 있는 이 계정의 데이터를 저장 폴더로 옮긴다 — 이미 있는 항목은 건너뛴다
  Future<void> handleWebImport(bool ko) async {
    final ok = await confirmDialog(
      context,
      ko
          ? '웹 바이블블록에 저장된 이 계정의 설교·예배·새벽·교재를 저장 폴더로 가져올까요?\n\n'
              '· 이미 가져온 항목은 다시 만들지 않습니다.\n'
              '· 웹의 원본은 지우지 않습니다.\n'
              '· 웹 브라우저에만 있던 기억된 지시어·학습 메모리는 옮겨지지 않습니다.'
          : 'Import this account\'s data from the web app into your data folder?\n\nExisting items are skipped and the web originals are kept.',
    );
    if (!ok) return;
    setState(() => webStatus = 'reading');
    try {
      final backup = await buildWebBackup();
      final added = await ref.storeRead.importBackup(backup);
      if (mounted) setState(() => webStatus = 'done:$added');
    } catch (e) {
      if (mounted) setState(() => webStatus = 'error:${'$e'.replaceFirst('Exception: ', '')}');
    }
  }

  Future<void> handleExport(String lang) async {
    final data = ref.storeRead.exportBackup();
    final date = todayString();
    final fileName = lang == 'en' ? 'Bible-and-Sermon-backup-$date.json' : '성경과설교-백업-$date.json';
    final ok = await saveTextFile(fileName, const JsonEncoder.withIndent('  ').convert(data));
    if (!ok || !mounted) return;
    setState(() => exportStatus = lang == 'en' ? 'Saved' : '저장됨');
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => exportStatus = null);
    });
  }

  Future<void> handleImport() async {
    final text = await pickJsonFile();
    if (text == null) return;
    setState(() => importStatus = 'reading');
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) throw Exception('잘못된 파일 형식입니다.');
      final added = await ref.storeRead.importBackup(json);
      if (mounted) setState(() => importStatus = 'done:$added');
    } catch (e) {
      if (mounted) setState(() => importStatus = 'error:${'$e'.replaceFirst('Exception: ', '')}');
    }
  }

  // ── 성경나침반 내설교 폴더 (읽기 전용) — 설교작성 사이드 목록에 보인다 ──
  String wbName = wordblokFolderName();
  bool wbPending = wordblokPermissionNeeded();

  Future<void> handlePickWordblok() async {
    try {
      final name = await pickWordblokFolder();
      if (name == null || !mounted) return;
      setState(() {
        wbName = name;
        wbPending = false;
      });
      widget.onWordblokChanged?.call();
    } catch (e) {
      if (mounted) showAlert(context, '$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> handleRestoreWordblok() async {
    final name = await requestWordblokPermission();
    if (name == null || !mounted) return;
    setState(() {
      wbName = name;
      wbPending = false;
    });
    widget.onWordblokChanged?.call();
  }

  void handleRefreshWordblok() {
    clearWordblokCache();
    widget.onWordblokChanged?.call();
  }

  /// 설정 칸의 테두리 버튼 — 글자색을 따로 줄 수 있는 OutlineBtn
  Widget _wbButton(String label, VoidCallback onPressed, Color color, {bool alignLeft = true}) {
    final c = context.c;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: c.bg,
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: c.border)),
        textStyle: const TextStyle(fontSize: 13),
      ),
      child: Text(label),
    );
  }

  /// 회원 탈퇴 — 구독은 스토어에서 따로 해지해야 하고, 폴더의 파일은 남는다는 것을 알린 뒤 한 번 더 확인
  Future<void> _confirmDelete(bool ko) async {
    final ok = await confirmDialog(
      context,
      ko
          ? '회원 탈퇴하시겠습니까?\n\n'
              '· 계정과 로그인 정보가 삭제되며 되돌릴 수 없습니다.\n'
              '· 구독 중이라면 App Store·Google Play 에서 따로 해지하셔야 합니다.\n'
              '· 저장 폴더에 있는 설교·교재 파일은 지워지지 않고 그대로 남습니다.'
          : 'Delete your account?\n\n'
              '· Your account and sign-in data will be deleted permanently.\n'
              '· Cancel any subscription separately in the App Store or Google Play.\n'
              '· Files in your data folder are kept.',
    );
    if (!ok) return;
    try {
      await deleteAccount();
      widget.onClose();
    } catch (e) {
      if (mounted) showAlert(context, '$e'.replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final store = ref.store;
    final lang = settings.lang;
    final ko = lang == 'ko';

    Widget section(String label, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(label.toUpperCase(),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.textMuted, letterSpacing: 0.8)),
            ),
            ...children,
          ]),
        );

    Widget options(List<Option> items, String value, ValueChanged<String> onSelect) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final o in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: OutlineBtn(o.label(lang), alignLeft: true, active: value == o.code, onPressed: () => onSelect(o.code)),
              ),
          ],
        );

    Widget card({required String caption, required String body, required VoidCallback onDelete}) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: c.bg, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(6)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(caption, style: TextStyle(fontSize: 11, color: c.textMuted))),
              InkWell(onTap: onDelete, child: Text('×', style: TextStyle(fontSize: 16, color: c.textMuted))),
            ]),
            const SizedBox(height: 4),
            Text(body, style: TextStyle(fontSize: 12, color: c.text)),
          ]),
        );

    String stepLabel(String key) {
      final sep = key.indexOf('_');
      if (sep < 0) return key;
      final tab = key.substring(0, sep);
      final stepKey = key.substring(sep + 1);
      final steps = tabs.contains(tab) ? stepsForTab(tab) : const <StepDef>[];
      final step = steps.where((s) => s.key == stepKey).firstOrNull;
      final tabName = tabs.contains(tab) ? tabLabel(tab, lang) : tab;
      return '$tabName · ${step?.ko ?? stepKey}';
    }

    final memoryCards = <Widget>[
      for (final entry in store.memories.entries)
        for (var i = 0; i < entry.value.length; i++)
          card(
            caption: '${stepLabel(entry.key)} · ${entry.value[i].date}',
            body: entry.value[i].text,
            onDelete: () => store.deleteMemory(entry.key, i),
          ),
    ];

    return Container(
      width: 260,
      decoration: BoxDecoration(color: c.bgSidebar, border: Border(left: BorderSide(color: c.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
          child: Row(children: [
            Expanded(child: Text(ko ? '설정' : 'Settings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: c.textHeading))),
            InkWell(onTap: widget.onClose, child: Text('×', style: TextStyle(fontSize: 18, color: c.textMuted))),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            section(ko ? '데이터 백업' : 'Backup', [
              OutlineBtn(ko ? '내보내기 (백업 파일 저장)' : 'Export Backup', alignLeft: true, onPressed: () => handleExport(lang)),
              const SizedBox(height: 8),
              OutlineBtn(ko ? '불러오기 (백업 파일 추가)' : 'Import Backup', alignLeft: true, onPressed: handleImport),
              if (exportStatus != null)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(exportStatus!, style: const TextStyle(fontSize: 12, color: AppColors.success))),
              if (importStatus == 'reading')
                Padding(padding: const EdgeInsets.only(top: 8), child: Text('불러오는 중...', style: TextStyle(fontSize: 12, color: c.textMuted))),
              if (importStatus?.startsWith('done:') == true)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(ko ? '완료! ${importStatus!.substring(5)}개 항목을 더했습니다.' : 'Done! Added ${importStatus!.substring(5)} items.',
                      style: const TextStyle(fontSize: 12, color: AppColors.success)),
                ),
              const SizedBox(height: 8),
              OutlineBtn(ko ? '웹 바이블블록에서 가져오기' : 'Import from Web App', alignLeft: true, onPressed: webStatus == 'reading' ? null : () => handleWebImport(ko)),
              if (webStatus == 'reading')
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(ko ? '가져오는 중...' : 'Importing...', style: TextStyle(fontSize: 12, color: c.textMuted))),
              if (webStatus?.startsWith('done:') == true)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(ko ? '완료! ${webStatus!.substring(5)}개 항목을 가져왔습니다.' : 'Done! Imported ${webStatus!.substring(5)} items.',
                      style: const TextStyle(fontSize: 12, color: AppColors.success)),
                ),
              if (webStatus?.startsWith('error:') == true)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(webStatus!.substring(6), style: const TextStyle(fontSize: 12, color: AppColors.danger))),
              if (importStatus?.startsWith('error:') == true)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(importStatus!.substring(6), style: const TextStyle(fontSize: 12, color: AppColors.danger))),
            ]),
            section(ko ? '테마' : 'Theme', [options(themes, settings.theme, (v) => notifier.update(settings.copyWith(theme: v)))]),
            section(ko ? '언어' : 'Language', [options(languages, settings.lang, notifier.setLang)]),
            section(ko ? '저장 폴더' : 'Data Folder', [
              Text(store.fs.displayName, style: TextStyle(fontSize: 13, color: c.text)),
              const SizedBox(height: 8),
              if (usesAutoFolder)
                // iPhone·iPad 는 iCloud Drive 폴더, Android 는 앱 전용 폴더를 쓴다
                Text(
                  store.fs.displayName.startsWith('iCloud')
                      ? (ko ? '같은 iCloud 를 쓰는 iPhone·iPad·Mac 에서 함께 볼 수 있습니다.\nMac 에서는 iCloud Drive 의 성경과설교 폴더를 고르세요.' : 'Shared with your iPhone, iPad and Mac on the same iCloud.\nOn Mac, choose the 성경과설교 folder in iCloud Drive.')
                      : store.fs.displayName.startsWith('이 기기')
                          ? (ko ? 'iCloud 에 로그인하면 iCloud Drive 에 저장되어 다른 기기에서도 볼 수 있습니다.' : 'Sign in to iCloud to save in iCloud Drive and share with other devices.')
                          : (ko ? '이 기기의 앱 전용 폴더에 저장됩니다.\n다른 기기로 옮길 때는 위의 백업 내보내기·불러오기를 쓰세요.' : 'Saved in this app\'s own folder on this device.\nUse Export/Import Backup above to move to another device.'),
                  style: TextStyle(fontSize: 12, color: c.textMuted, height: 1.5),
                )
              else
                OutlineBtn(ko ? '다른 폴더로 변경' : 'Change Folder', alignLeft: true, onPressed: () => ref.read(folderProvider).pickFolder()),
            ]),
            section(ko ? '성경나침반 내설교 폴더' : 'WordBlok Sermon Folder', [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  ko ? '성경나침반의 설교 파일(.scb)을 설교작성 목록에서 읽을 수 있습니다.' : 'Read WordBlok sermon files (.scb) in the sermon list.',
                  style: TextStyle(fontSize: 12, color: c.textMuted, height: 1.5),
                ),
              ),
              if (wbName.isNotEmpty)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(wbName, style: TextStyle(fontSize: 13, color: c.text))),
              if (wbPending)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _wbButton(ko ? '권한 다시 허용' : 'Allow Access Again', handleRestoreWordblok, const Color(0xFFF59E0B)),
                ),
              Row(children: [
                Expanded(
                  child: _wbButton(
                      wbName.isNotEmpty ? (ko ? '다른 폴더로 변경' : 'Change Folder') : (ko ? '폴더 선택' : 'Choose Folder'), handlePickWordblok, c.text),
                ),
                if (wbName.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _wbButton(ko ? '새로고침' : 'Refresh', handleRefreshWordblok, c.textMuted, alignLeft: false),
                ],
              ]),
            ]),
            section(ko ? '계정' : 'Account', [
              if (ref.watch(authUserProvider).valueOrNull case final user?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('${providerLabel(user)} · ${user.email ?? ''}', style: TextStyle(fontSize: 12, color: c.textMuted)),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  switch (ref.watch(subscriptionProvider).valueOrNull) {
                    SubscriptionState(active: true, :final expiresAt) =>
                      '${ko ? '구독' : 'Subscription'}: ${ko ? '사용 중' : 'Active'}${expiresAt != null ? ' (~${expiresAt.toLocal().toIso8601String().substring(0, 10)})' : ''}',
                    SubscriptionState(ready: false) => ko ? '구독: 준비 중' : 'Subscription: coming soon',
                    _ => ko ? '구독: 없음' : 'Subscription: none',
                  },
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
              ),
              OutlineBtn(ko ? '로그아웃' : 'Sign out', alignLeft: true, onPressed: () async {
                // 패널이 닫힌 뒤에도 쓸 수 있도록 먼저 잡아 둔다
                final container = ProviderScope.containerOf(context, listen: false);
                widget.onClose();
                await signOut();
                // 알림이 늦거나 빠져도 로그인 상태를 다시 읽어 로그인 화면으로 바꾼다
                container.invalidate(authUserProvider);
              }),
              const SizedBox(height: 8),
              OutlineBtn(ko ? '회원 탈퇴' : 'Delete Account', alignLeft: true, onPressed: () => _confirmDelete(ko)),
            ]),
            if (store.defaultKeywords.isNotEmpty)
              section(ko ? '기억된 지시어' : 'Saved Keywords', [
                for (final e in store.defaultKeywords.entries)
                  card(caption: stepLabel(e.key), body: e.value, onDelete: () => store.removeKeyword(e.key)),
              ]),
            section(ko ? '학습된 메모리' : 'Learned Memory', [
              if (memoryCards.isEmpty)
                Text(
                  ko
                      ? '아직 저장된 메모리가 없습니다.\n키워드 입력창에 내용을 입력하고 "기억해줘"를 붙이면 자동으로 쌓입니다.'
                      : 'No memories saved yet.\nType a keyword and add "remember this" to accumulate.',
                  style: TextStyle(fontSize: 12, color: c.textMuted, height: 1.6),
                )
              else
                ...memoryCards,
            ]),
            section(ko ? '앱 정보' : 'About', [
              Text('${appName(lang)} ${version ?? ''}', style: TextStyle(fontSize: 13, color: c.text)),
              const SizedBox(height: 8),
              OutlineBtn(ko ? '업데이트 확인' : 'Check for Updates', alignLeft: true, onPressed: updateStatus == 'checking' ? null : handleCheckUpdate),
              if (updateStatus == 'checking')
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(ko ? '확인 중...' : 'Checking...', style: TextStyle(fontSize: 12, color: c.textMuted))),
              if (updateStatus == 'latest')
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(ko ? '최신 버전입니다.' : 'You are up to date.', style: const TextStyle(fontSize: 12, color: AppColors.success))),
              if (updateStatus == 'error')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(ko ? '확인하지 못했습니다. 인터넷 연결을 확인해 주세요.' : 'Could not check. Please check your connection.', style: const TextStyle(fontSize: 12, color: AppColors.danger)),
                ),
              if (updateStatus == 'available' && update != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(ko ? '새 버전(${update!.latest})이 있습니다.' : 'Version ${update!.latest} is available.', style: TextStyle(fontSize: 12, color: c.accent)),
                ),
                if (isWebPlatform)
                  AccentButton(ko ? '새로고침해서 업데이트' : 'Reload to Update', onPressed: () => applyUpdate(update!))
                else if ((update!.url ?? '').isNotEmpty)
                  AccentButton(
                    updatesFromStore ? (ko ? '스토어에서 업데이트' : 'Update in Store') : (ko ? '새 버전 받기' : 'Download'),
                    onPressed: () => applyUpdate(update!),
                  )
                else
                  Text(ko ? '곧 받을 수 있습니다.' : 'It will be available soon.', style: TextStyle(fontSize: 12, color: c.textMuted)),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }
}
