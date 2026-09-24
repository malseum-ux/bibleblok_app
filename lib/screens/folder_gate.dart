// 저장 폴더 연결 화면 — 처음 실행, 새로고침 뒤 권한 복원, 지원하지 않는 브라우저 안내
// (웹 AuthGate.jsx 의 카드 모양을 그대로 쓴다)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants.dart';
import '../providers/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/ui.dart';

class FolderGate extends ConsumerWidget {
  const FolderGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final folder = ref.watch(folderProvider);
    final lang = ref.watch(settingsProvider).lang;
    final ko = lang == 'ko';

    if (folder.status == FolderStatus.checking) return Scaffold(backgroundColor: c.bg);

    final (String message, String? button, VoidCallback? onPressed) = switch (folder.status) {
      FolderStatus.needPermission => (
          ko ? '이전에 연결한 저장 폴더를 다시 열려면\n접근 권한을 허용해 주세요.' : 'Allow access to reopen\nyour data folder.',
          ko ? '폴더 권한 허용' : 'Allow Access',
          () => ref.read(folderProvider).requestPermission(),
        ),
      FolderStatus.unsupported => (
          ko
              ? '이 브라우저는 폴더 저장을 지원하지 않습니다.\nChrome 또는 Edge 에서 열어 주세요.'
              : 'This browser does not support folder storage.\nPlease use Chrome or Edge.',
          null,
          null,
        ),
      _ => (
          ko
              ? '설교와 자료를 저장할 폴더를 선택해 주세요.\niCloud Drive·Google Drive·Dropbox 폴더를 고르면\n여러 기기에서 함께 쓸 수 있습니다.'
              : 'Choose a folder to store your work.\nPick an iCloud Drive, Google Drive or Dropbox folder\nto use it on all your devices.',
          ko ? '저장 폴더 선택' : 'Choose Folder',
          () => ref.read(folderProvider).pickFolder(),
        ),
    };

    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
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
            Text(message, style: TextStyle(fontSize: 13, color: c.textMuted, height: 1.6)),
            const SizedBox(height: 24),
            if (button != null) AccentButton(button, onPressed: onPressed, padding: const EdgeInsets.symmetric(vertical: 11)),
            if (folder.status == FolderStatus.needPermission) ...[
              const SizedBox(height: 8),
              OutlineBtn(ko ? '다른 폴더 선택' : 'Choose Another Folder', onPressed: () => ref.read(folderProvider).pickFolder()),
            ],
            if (folder.error != null) ...[
              const SizedBox(height: 10),
              Text(folder.error!, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
            ],
          ]),
        ),
      ),
    );
  }
}
