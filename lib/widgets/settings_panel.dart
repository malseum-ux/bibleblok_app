// 설정 — 웹 SettingsPanel.jsx 와 같은 배치 (오른쪽에서 열리는 260px 패널)
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants.dart';
import '../providers/app_state.dart';
import '../providers/auth.dart';
import '../services/file_io.dart';
import '../theme/app_colors.dart';
import 'ui.dart';

class SettingsPanel extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  const SettingsPanel({super.key, required this.onClose});

  @override
  ConsumerState<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends ConsumerState<SettingsPanel> {
  String? exportStatus;
  String? importStatus; // reading | done:n | error:메시지

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
              if (importStatus?.startsWith('error:') == true)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(importStatus!.substring(6), style: const TextStyle(fontSize: 12, color: AppColors.danger))),
            ]),
            section(ko ? '테마' : 'Theme', [options(themes, settings.theme, (v) => notifier.update(settings.copyWith(theme: v)))]),
            section(ko ? '언어' : 'Language', [options(languages, settings.lang, notifier.setLang)]),
            section(ko ? '성경 번역본' : 'Bible Version', [
              options(lang == 'en' ? bibleVersionsEn : bibleVersionsKo, settings.bible, (v) => notifier.update(settings.copyWith(bible: v))),
            ]),
            section(ko ? '저장 폴더' : 'Data Folder', [
              Text(store.fs.displayName, style: TextStyle(fontSize: 13, color: c.text)),
              const SizedBox(height: 8),
              OutlineBtn(ko ? '다른 폴더로 변경' : 'Change Folder', alignLeft: true, onPressed: () => ref.read(folderProvider).pickFolder()),
            ]),
            section(ko ? '계정' : 'Account', [
              if (ref.watch(authUserProvider).valueOrNull case final user?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('${providerLabel(user)} · ${user.email ?? ''}', style: TextStyle(fontSize: 12, color: c.textMuted)),
                ),
              OutlineBtn(ko ? '로그아웃' : 'Sign out', alignLeft: true, onPressed: () {
                widget.onClose();
                signOut();
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
          ]),
        ),
      ]),
    );
  }
}
