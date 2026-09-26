// 메인 화면 — 웹 App.jsx 와 같은 배치
// 헤더(메뉴·로고·탭·검색·설정) / 사이드바 + 너비 조절 / 작업 영역
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants.dart';
import '../models/item.dart';
import '../providers/app_state.dart';
import '../services/store.dart';
import '../theme/app_colors.dart';
import '../widgets/forms.dart';
import '../widgets/settings_panel.dart';
import '../widgets/sidebar.dart';
import '../widgets/ui.dart';
import 'cell_view.dart';
import 'step_view.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String tab = 'sermon';
  String? selectedId;
  String? selectedFolder;

  /// 선택된 폴더가 [path] 이거나 그 안쪽인지 — 폴더 이름·위치가 바뀌면 선택을 풀 때 쓴다
  static bool _isInside(String? selected, String path) => selected != null && (selected == path || selected.startsWith('$path/'));
  bool settingsOpen = false;
  bool? sidebarVisible; // null = 화면 폭으로 결정 (넓으면 보임)
  double sidebarWidth = 240;
  bool searchOpen = false;
  final searchCtrl = TextEditingController();
  String searchMode = 'sermon-title'; // sermon-title | sermon-content | worship
  List<Item>? searchResults;
  bool searchLoading = false;
  final Map<String, double> fontSizes = {'sermon': 14, 'worship': 14, 'dawn': 14, 'cell': 14};
  bool creating = false; // 새 항목 저장 중 — 여러 번 눌러도 한 번만 만든다
  bool resizeHover = false;

  Store get store => ref.read(folderProvider).store!;

  void switchTab(String t) => setState(() {
        tab = t;
        selectedId = null;
        selectedFolder = null;
        closeSearch();
      });

  void closeSearch() {
    searchOpen = false;
    searchCtrl.clear();
    searchResults = null;
  }

  // ── 검색 ─────────────────────────────────────────────────────────────────

  String _date6(Item i) => (i.date ?? '').replaceAll('-', '').length >= 2 ? (i.date ?? '').replaceAll('-', '').substring(2) : '';

  void runLiveSearch() {
    if (!searchOpen || searchMode == 'sermon-content') return;
    final q = searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => searchResults = null);
      return;
    }
    final s = store;
    setState(() {
      if (searchMode == 'sermon-title') {
        searchResults = [...s.items['sermon']!, ...s.items['dawn']!].where((i) {
          final name = i.title?.isNotEmpty == true ? i.title! : (i.passage ?? '');
          return '${_date6(i)} $name'.toLowerCase().contains(q);
        }).toList();
      } else {
        searchResults = s.items['worship']!.where((i) => '${_date6(i)} 예배인도'.toLowerCase().contains(q)).toList();
      }
    });
  }

  void runContentSearch() {
    if (searchMode != 'sermon-content') return;
    final q = searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return;
    setState(() => searchLoading = true);
    final matched = <Item>[];
    for (final i in [...store.items['sermon']!, ...store.items['dawn']!]) {
      final basic = [i.title, i.passage, i.category, i.emphasis].whereType<String>().join(' ').toLowerCase();
      if (basic.contains(q) || (i.draft ?? '').toLowerCase().contains(q) || i.steps.values.any((v) => v.toLowerCase().contains(q))) {
        matched.add(i);
      }
    }
    setState(() {
      searchResults = matched;
      searchLoading = false;
    });
  }

  // ── 항목·폴더 처리 ─────────────────────────────────────────────────────────

  Future<void> handleCreateNew(Map<String, String?> data) async {
    if (creating) return;
    creating = true;
    try {
      final item = await store.createItem(tab, data, selectedFolder ?? '');
      setState(() => selectedId = item.id);
    } catch (e) {
      if (mounted) showAlert(context, '${lang == 'ko' ? '저장 실패: ' : 'Save failed: '}$e');
    } finally {
      creating = false;
    }
  }

  Future<void> handleDelete(Item item) async {
    if (!await confirmDialog(context, lang == 'ko' ? '삭제하시겠습니까?' : 'Delete?')) return;
    await store.deleteItem(item);
    if (selectedId == item.id) setState(() => selectedId = null);
  }

  Future<void> handleDeleteFolder(String path) async {
    if (!await confirmDialog(context, '폴더를 삭제하시겠습니까? 하위폴더와 파일은 루트로 이동됩니다.')) return;
    try {
      await store.deleteFolder(tab, path);
    } catch (e) {
      if (mounted) showAlert(context, '${lang == 'ko' ? '폴더 삭제 실패: ' : 'Folder delete failed: '}$e');
      return;
    }
    setState(() => selectedFolder = null);
  }

  Future<void> _guard(Future<void> Function() action, String koMsg, String enMsg) async {
    try {
      await action();
    } catch (e) {
      if (mounted) showAlert(context, '${lang == 'ko' ? koMsg : enMsg}${'$e'.replaceFirst('Exception: ', '')}');
    }
  }

  String get lang => ref.read(settingsProvider).lang;

  // ── 화면 ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final settings = ref.watch(settingsProvider);
    final s = ref.store;
    final lang = settings.lang;
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 900;
    final showSidebar = sidebarVisible ?? !isMobile;
    final items = s.items[tab]!;
    Item? selectedItem;
    if (selectedId != null) {
      for (final t in tabs) {
        selectedItem ??= s.find(t, selectedId!);
      }
    }

    final sidebar = Sidebar(
      key: ValueKey('sidebar-$tab'),
      tab: tab,
      items: items,
      folders: s.folders[tab]!,
      selectedItemId: selectedId,
      selectedFolder: selectedFolder,
      onSelect: (item) => setState(() {
        // 다른 탭의 검색 결과를 누르면 그 탭으로 옮겨 연다
        if (item.tab != tab) tab = item.tab;
        selectedId = item.id;
        if (isMobile) sidebarVisible = false;
      }),
      onDelete: handleDelete,
      onCreateFolder: (name) => _guard(() => s.createFolder(tab, selectedFolder ?? '', name), '폴더 만들기 실패: ', 'Create failed: '),
      onDeleteFolder: handleDeleteFolder,
      onMoveItem: (item, folder) => _guard(() => s.moveItem(item, folder), '이동 실패: ', 'Move failed: '),
      onMoveFolder: (path, parent) => _guard(() async {
        await s.moveFolder(tab, path, parent);
        if (_isInside(selectedFolder, path)) setState(() => selectedFolder = null);
      }, '이동 실패: ', 'Move failed: '),
      onFolderSelect: (path) => setState(() {
        selectedFolder = path;
        selectedId = null;
      }),
      onRenameFolder: (path, name) => _guard(() async {
        await s.renameFolder(tab, path, name);
        if (_isInside(selectedFolder, path)) setState(() => selectedFolder = null);
      }, '이름 변경 실패: ', 'Rename failed: '),
      width: isMobile ? 280 : sidebarWidth,
      searchItems: searchResults,
      searchItemsTab: searchMode == 'worship' ? 'worship' : 'sermon',
      lang: lang,
    );

    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(children: [
        Column(children: [
          _header(context, lang, isMobile, showSidebar),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!isMobile && showSidebar) sidebar,
              if (!isMobile && showSidebar) _resizeHandle(c),
              Expanded(child: Container(color: c.bg, child: _main(context, lang, isMobile, selectedItem, settings))),
            ]),
          ),
        ]),
        // 모바일 사이드바 — 화면 위에 덮는다
        if (isMobile && showSidebar) ...[
          Positioned.fill(
            top: 48,
            child: GestureDetector(onTap: () => setState(() => sidebarVisible = false), child: Container(color: Colors.black.withValues(alpha: 0.4))),
          ),
          Positioned(top: 48, left: 0, bottom: 0, width: 280, child: sidebar),
        ],
        if (settingsOpen) ...[
          Positioned.fill(
            child: GestureDetector(onTap: () => setState(() => settingsOpen = false), child: Container(color: Colors.black.withValues(alpha: 0.25))),
          ),
          Positioned(top: 0, right: 0, bottom: 0, child: SettingsPanel(onClose: () => setState(() => settingsOpen = false))),
        ],
      ]),
    );
  }

  Widget _resizeHandle(AppColors c) => MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => resizeHover = true),
        onExit: (_) => setState(() => resizeHover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) => setState(() => sidebarWidth = (sidebarWidth + d.delta.dx).clamp(140, 520)),
          child: AnimatedContainer(duration: const Duration(milliseconds: 150), width: 5, color: resizeHover ? c.accent : c.border),
        ),
      );

  Widget _header(BuildContext context, String lang, bool isMobile, bool showSidebar) {
    final c = context.c;
    final en = lang == 'en';
    final modes = en
        ? const [('sermon-title', 'Sermon Title'), ('sermon-content', 'Sermon Content'), ('worship', 'Worship')]
        : const [('sermon-title', '설교제목'), ('sermon-content', '설교내용'), ('worship', '예배인도')];

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: c.bgSidebar, border: Border(bottom: BorderSide(color: c.border))),
      child: Row(children: [
        BoxIconButton(icon: Icons.menu, onPressed: () => setState(() => sidebarVisible = !showSidebar)),
        const SizedBox(width: 12),
        // 로고 + 앱 이름 (워드블록과 같은 모양: 28px, 둥글기 8, 간격 8)
        ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset('assets/logo-64.png', width: 28, height: 28, fit: BoxFit.cover)),
        if (!isMobile) ...[
          const SizedBox(width: 8),
          Text(appName(lang), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: c.textHeading, letterSpacing: -0.3)),
          const SizedBox(width: 12),
          Container(width: 1, height: 20, color: c.border),
        ],
        const SizedBox(width: 12),
        // 탭은 남은 공간만 차지하고, 좁으면 좌우로 밀어서 본다 (검색·설정 버튼이 밀려나지 않게)
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final t in tabs)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: TextButton(
                    onPressed: () => switchTab(t),
                    style: TextButton.styleFrom(
                      backgroundColor: tab == t ? c.accent : Colors.transparent,
                      foregroundColor: tab == t ? Colors.white : c.textMuted,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    child: Text(tabLabel(t, lang)),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(width: 12),
        if (searchOpen) ...[
          Container(
            decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(6)),
            clipBehavior: Clip.antiAlias,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < modes.length; i++)
                InkWell(
                  onTap: () => setState(() {
                    searchMode = modes[i].$1;
                    searchResults = null;
                    searchCtrl.clear();
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: searchMode == modes[i].$1 ? c.accent : Colors.transparent,
                      border: i < modes.length - 1 ? Border(right: BorderSide(color: c.border)) : null,
                    ),
                    child: Text(modes[i].$2,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: searchMode == modes[i].$1 ? Colors.white : c.textMuted)),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 220,
            child: CallbackShortcutsEsc(
              onEsc: () => setState(closeSearch),
              child: TextField(
                controller: searchCtrl,
                autofocus: true,
                onChanged: (_) => runLiveSearch(),
                onSubmitted: (_) => runContentSearch(),
                style: TextStyle(fontSize: 13, color: c.text),
                decoration: appInputDecoration(
                  context,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  hint: en
                      ? (searchMode == 'sermon-content' ? 'Search content, press Enter...' : searchMode == 'worship' ? 'Search by date...' : 'Search sermon title...')
                      : (searchMode == 'sermon-content' ? '설교내용 검색 후 Enter...' : searchMode == 'worship' ? '날짜 검색...' : '설교 제목 검색...'),
                ),
              ),
            ),
          ),
          if (searchLoading) Padding(padding: const EdgeInsets.only(left: 6), child: Text('검색 중...', style: TextStyle(fontSize: 12, color: c.textMuted))),
          InkWell(
            onTap: () => setState(closeSearch),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text('×', style: TextStyle(fontSize: 16, color: c.textMuted))),
          ),
          const SizedBox(width: 12),
        ],
        BoxIconButton(icon: Icons.search, tooltip: '찾기', active: searchOpen, onPressed: () => setState(() => searchOpen ? closeSearch() : searchOpen = true)),
        const SizedBox(width: 12),
        BoxIconButton(icon: Icons.settings_outlined, tooltip: lang == 'ko' ? '설정' : 'Settings', onPressed: () => setState(() => settingsOpen = true)),
      ]),
    );
  }

  Widget _main(BuildContext context, String lang, bool isMobile, Item? selectedItem, AppSettings settings) {
    final c = context.c;
    if (selectedItem == null) {
      if (tab == 'cell') {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(lang == 'en' ? 'Create New Cell Material' : '새 나눔 교재 만들기',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: c.textHeading)),
                const SizedBox(height: 20),
                CellForm(key: ValueKey('new-cell-$selectedFolder'), lang: lang, onSave: handleCreateNew),
              ]),
            ),
          ),
        );
      }
      // 새 항목 양식 (웹 ItemDetail item=null)
      final heading = lang == 'en'
          ? const {'sermon': 'Sermon', 'worship': 'Worship Order', 'dawn': 'Dawn Prayer'}[tab]!
          : const {'sermon': '설교 작성', 'worship': '예배인도문 작성', 'dawn': '새벽 설교 작성'}[tab]!;
      final folderName = selectedFolder == null ? null : baseName(selectedFolder!);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(heading, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.textHeading)),
          const SizedBox(height: 16),
          if (tab == 'worship')
            WorshipForm(key: ValueKey('new-worship-$selectedFolder'), lang: lang, bible: settings.bible, onSave: handleCreateNew)
          else
            SermonDawnForm(
              key: ValueKey('new-$tab-$selectedFolder'),
              isDawn: tab == 'dawn',
              lang: lang,
              defaultCategory: folderName,
              onSave: handleCreateNew,
            ),
        ]),
      );
    }

    if (selectedItem.tab == 'cell') {
      return CellView(
        key: ValueKey(selectedItem.id),
        item: selectedItem,
        lang: lang,
        bible: settings.bible,
        fontSize: fontSizes['cell']!,
        onFontSizeChange: (v) => setState(() => fontSizes['cell'] = v),
        isMobile: isMobile,
        onGoToSermon: (sermon) => setState(() {
          tab = sermon.tab;
          selectedId = sermon.id;
          selectedFolder = null;
          closeSearch();
        }),
      );
    }
    return StepView(
      key: ValueKey(selectedItem.id),
      item: selectedItem,
      lang: lang,
      bible: settings.bible,
      fontSize: fontSizes[selectedItem.tab]!,
      onFontSizeChange: (v) => setState(() => fontSizes[selectedItem.tab] = v),
      isMobile: isMobile,
      onGoToCell: (cell) => setState(() {
        tab = 'cell';
        selectedId = cell.id;
        selectedFolder = null;
        closeSearch();
      }),
    );
  }
}
