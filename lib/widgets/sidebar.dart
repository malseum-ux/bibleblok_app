// 왼쪽 목록 — 웹 Sidebar.jsx 와 같은 배치·동작
// 폴더는 경로 문자열('창세기 강해/1부')로 구분한다 (저장 폴더의 실제 폴더와 같음)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/item.dart';
import '../services/store.dart' show parentOf, baseName;
import '../theme/app_colors.dart';

class _DragData {
  final bool isFolder;
  final String? folderPath;
  final Item? item;
  const _DragData.folder(this.folderPath)
      : isFolder = true,
        item = null;
  const _DragData.file(this.item)
      : isFolder = false,
        folderPath = null;
}

class Sidebar extends StatefulWidget {
  final String tab;
  final List<Item> items;
  final List<String> folders;
  final String? selectedItemId;
  final String? selectedFolder;
  final ValueChanged<Item> onSelect;
  final ValueChanged<Item> onDelete;
  final ValueChanged<String> onCreateFolder;
  final ValueChanged<String> onDeleteFolder;
  final void Function(Item item, String folder) onMoveItem;
  final void Function(String path, String newParent) onMoveFolder;
  final ValueChanged<String> onFolderSelect;
  final void Function(String path, String name) onRenameFolder;
  final double width;
  final List<Item>? searchItems;
  final String? searchItemsTab;
  final String lang;

  const Sidebar({
    super.key,
    required this.tab,
    required this.items,
    required this.folders,
    required this.selectedItemId,
    required this.selectedFolder,
    required this.onSelect,
    required this.onDelete,
    required this.onCreateFolder,
    required this.onDeleteFolder,
    required this.onMoveItem,
    required this.onMoveFolder,
    required this.onFolderSelect,
    required this.onRenameFolder,
    required this.width,
    this.searchItems,
    this.searchItemsTab,
    required this.lang,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final Set<String> expanded = {};
  bool creatingFolder = false;
  final newFolderCtrl = TextEditingController();
  String? movingItemId;
  String? editingFolder;
  final editCtrl = TextEditingController();
  String sortMode = 'date-desc'; // date-desc | date-asc | name-asc
  bool dragging = false;
  String? dropTarget; // 폴더 경로, '' = 루트, null = 없음

  bool get en => widget.lang == 'en';

  String labelOf(Item item) => item.label(widget.lang);

  List<Item> sortItems(List<Item> list) {
    final out = [...list];
    out.sort((a, b) {
      if (sortMode == 'date-desc') return (b.date ?? '').compareTo(a.date ?? '') > 0 ? 1 : -1;
      if (sortMode == 'date-asc') return (a.date ?? '').compareTo(b.date ?? '') > 0 ? 1 : -1;
      return labelOf(a).compareTo(labelOf(b));
    });
    return out;
  }

  void cycleSort() => setState(() {
        sortMode = sortMode == 'date-desc' ? 'date-asc' : (sortMode == 'date-asc' ? 'name-asc' : 'date-desc');
      });

  String get sortLabel => en
      ? (sortMode == 'date-desc' ? 'Date↓' : sortMode == 'date-asc' ? 'Date↑' : 'Name')
      : (sortMode == 'date-desc' ? '날짜↓' : sortMode == 'date-asc' ? '날짜↑' : '이름');

  String get tabLabel => en
      ? const {'sermon': 'Sermons', 'worship': 'Worship', 'cell': 'Cell Material', 'dawn': 'Dawn Prayer'}[widget.tab]!
      : const {'sermon': '설교 목록', 'worship': '예배 목록', 'cell': '교재 목록', 'dawn': '새벽 목록'}[widget.tab]!;

  void createFolder() {
    final name = newFolderCtrl.text.trim();
    if (name.isEmpty) return;
    widget.onCreateFolder(name);
    newFolderCtrl.clear();
    setState(() => creatingFolder = false);
  }

  void commitRename() {
    final path = editingFolder;
    if (path != null && editCtrl.text.trim().isNotEmpty) widget.onRenameFolder(path, editCtrl.text.trim());
    setState(() => editingFolder = null);
  }

  List<String> childrenOf(String parent) =>
      widget.folders.where((f) => parentOf(f) == parent).toList()..sort((a, b) => baseName(a).compareTo(baseName(b)));

  /// 트리 순서로 펼친 폴더 목록 (이동 메뉴용) — (경로, 깊이)
  List<(String, int)> flatFolders([String parent = '', int depth = 0]) => [
        for (final f in childrenOf(parent)) ...[(f, depth), ...flatFolders(f, depth + 1)],
      ];

  void _onDrop(_DragData data, String target) {
    if (data.isFolder) {
      final path = data.folderPath!;
      if (target == path || target.startsWith('$path/')) return;
      widget.onMoveFolder(path, target);
    } else {
      widget.onMoveItem(data.item!, target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final searching = widget.searchItems != null;
    final folderSet = widget.folders.toSet();
    final folderFiles = <String, List<Item>>{};
    final rootItems = <Item>[];
    for (final item in widget.items) {
      if (item.folder.isNotEmpty && folderSet.contains(item.folder)) {
        (folderFiles[item.folder] ??= []).add(item);
      } else {
        rootItems.add(item);
      }
    }
    final dawnNumbers = <String, int>{};
    if (widget.tab == 'dawn') {
      final sorted = sortItems(widget.items);
      for (var i = 0; i < sorted.length; i++) {
        dawnNumbers[sorted[i].id] = i + 1;
      }
    }
    final selectedFolderName = widget.selectedFolder == null ? null : baseName(widget.selectedFolder!);

    return Container(
      width: widget.width,
      decoration: BoxDecoration(color: c.bgSidebar, border: Border(right: BorderSide(color: c.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // 제목 줄: 목록 이름 · 정렬 · 새 폴더
        Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
          child: Row(children: [
            Expanded(
              child: Text(tabLabel.toUpperCase(),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textMuted, letterSpacing: 0.6)),
            ),
            _ghost(sortLabel, cycleSort, fontSize: 10, opacity: 0.7, tooltip: en ? 'Change sort order' : '정렬 방식 변경'),
            const SizedBox(width: 6),
            _ghost('+', () => setState(() => creatingFolder = true),
                fontSize: 15,
                opacity: 0.7,
                tooltip: selectedFolderName != null
                    ? (en ? 'Create subfolder in "$selectedFolderName"' : '"$selectedFolderName" 안에 하위폴더 생성')
                    : (en ? 'New folder' : '새 폴더')),
          ]),
        ),

        if (creatingFolder)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (selectedFolderName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(en ? 'Subfolder of "$selectedFolderName"' : '"$selectedFolderName" 하위폴더',
                      style: TextStyle(fontSize: 11, color: c.textMuted)),
                ),
              Row(children: [
                Expanded(
                  child: CallbackShortcutsEsc(
                    onEsc: () => setState(() => creatingFolder = false),
                    child: TextField(
                      controller: newFolderCtrl,
                      autofocus: true,
                      onSubmitted: (_) => createFolder(),
                      style: TextStyle(fontSize: 12, color: c.text),
                      decoration: _smallInput(context, en ? 'Folder name' : '폴더 이름'),
                    ),
                  ),
                ),
                _ghost('확인', createFolder, opacity: 1, color: c.accent),
              ]),
            ]),
          ),

        Expanded(
          child: searching
              ? ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: [
                  if (widget.searchItems!.isEmpty)
                    _emptyText('검색 결과 없음')
                  else
                    for (final item in widget.searchItems!) _fileRow(item, 0, dawnNumbers),
                ])
              : DragTarget<_DragData>(
                  // 목록 빈 곳에 놓으면 루트로 이동
                  onWillAcceptWithDetails: (_) {
                    if (dropTarget == null) setState(() => dropTarget = '');
                    return true;
                  },
                  onLeave: (_) => setState(() => dropTarget = null),
                  onAcceptWithDetails: (d) {
                    _onDrop(d.data, '');
                    setState(() => dropTarget = null);
                  },
                  builder: (context, _, _) => ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: [
                    for (final f in childrenOf('')) ..._folderRows(f, 0, folderFiles, dawnNumbers),
                    if (widget.folders.isNotEmpty && rootItems.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: dropTarget == '' && dragging ? c.accentLight : Colors.transparent,
                          border: Border(top: BorderSide(color: c.border)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Opacity(
                          opacity: dropTarget == '' && dragging ? 1 : 0.6,
                          child: Text(
                            dropTarget == '' && dragging
                                ? (en ? 'Drop here → Move to root' : '여기에 드롭 → 루트로 이동')
                                : (en ? 'No folder' : '폴더 없음'),
                            style: TextStyle(fontSize: 11, color: c.textMuted),
                          ),
                        ),
                      ),
                    if (rootItems.isEmpty && widget.folders.isEmpty) _emptyText(_emptyHint()),
                    for (final item in sortItems(rootItems)) _fileRow(item, 0, dawnNumbers),
                    if (dragging)
                      Container(
                        height: 40,
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
                        child: Opacity(
                          opacity: dropTarget == '' ? 1 : 0.4,
                          child: Text(
                            dropTarget == '' ? (en ? 'Move to root' : '루트로 이동') : (en ? 'Drag to folder' : '폴더로 드래그'),
                            style: TextStyle(fontSize: 11, color: dropTarget == '' ? c.accent : c.textMuted),
                          ),
                        ),
                      ),
                  ]),
                ),
        ),
      ]),
    );
  }

  String _emptyHint() => en
      ? const {'sermon': 'Use + to add a sermon', 'worship': 'Use + to add a worship service', 'cell': 'Use + to add cell material', 'dawn': 'Use + to add a dawn prayer'}[widget.tab]!
      : const {'sermon': '+ 버튼으로 설교를 추가하세요', 'worship': '+ 버튼으로 예배를 추가하세요', 'cell': '+ 버튼으로 교재를 추가하세요', 'dawn': '+ 버튼으로 새벽 기도를 추가하세요'}[widget.tab]!;

  Widget _emptyText(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Opacity(
          opacity: 0.6,
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: context.c.textMuted)),
        ),
      );

  InputDecoration _smallInput(BuildContext context, String hint) {
    final c = context.c;
    OutlineInputBorder b(Color color) => OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: color));
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
      filled: true,
      fillColor: c.bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      border: b(c.border),
      enabledBorder: b(c.border),
      focusedBorder: b(c.border),
    );
  }

  Widget _ghost(String label, VoidCallback onTap, {double fontSize = 13, double opacity = 0.4, Color? color, String? tooltip}) {
    final w = InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Opacity(
          opacity: opacity,
          child: Text(label, style: TextStyle(fontSize: fontSize, color: color ?? context.c.textMuted)),
        ),
      ),
    );
    return tooltip == null ? w : Tooltip(message: tooltip, child: w);
  }

  Widget _ghostIcon(IconData icon, VoidCallback onTap, {String? tooltip}) {
    final w = InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Opacity(opacity: 0.4, child: Icon(icon, size: 11, color: context.c.textMuted)),
      ),
    );
    return tooltip == null ? w : Tooltip(message: tooltip, child: w);
  }

  // 0.5초 길게 누르면 끌기 시작 (웹과 같은 지연)
  Widget _draggable({required _DragData data, required String label, required Widget child}) {
    final c = context.c;
    return LongPressDraggable<_DragData>(
      data: data,
      delay: const Duration(milliseconds: 500),
      onDragStarted: () => setState(() => dragging = true),
      onDragEnd: (_) => setState(() {
        dragging = false;
        dropTarget = null;
      }),
      feedback: Material(
        color: Colors.transparent,
        child: Transform.translate(
          offset: const Offset(14, -10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: c.accent,
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 10, offset: Offset(0, 3))],
            ),
            child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      child: child,
    );
  }

  Widget _fileRow(Item item, int depth, Map<String, int> dawnNumbers) {
    final c = context.c;
    final selected = widget.selectedItemId == item.id;
    final moving = movingItemId == item.id;
    final label = labelOf(item);
    final row = InkWell(
      onTap: () => widget.onSelect(item),
      child: Container(
        padding: EdgeInsets.only(left: 10.0 + depth * 14, right: 8, top: 4, bottom: 4),
        decoration: BoxDecoration(
          color: selected ? c.accentLight : Colors.transparent,
          border: Border(left: BorderSide(color: selected ? c.accent : Colors.transparent, width: 2)),
        ),
        child: Row(children: [
          if (widget.tab == 'dawn' && dawnNumbers[item.id] != null)
            Container(
              constraints: const BoxConstraints(minWidth: 18),
              padding: const EdgeInsets.only(right: 4),
              child: Text('${dawnNumbers[item.id]}.', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: c.textMuted)),
            ),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: selected ? c.accent : c.text)),
          ),
          // 웹의 ↪ / ✕ (글꼴에 없는 기호라 아이콘으로)
          _ghostIcon(moving ? Icons.close : Icons.subdirectory_arrow_right, () => setState(() => movingItemId = moving ? null : item.id),
              tooltip: en ? 'Move to folder' : '폴더 이동'),
          _ghost('×', () => widget.onDelete(item)),
        ]),
      ),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      widget.searchItems != null ? row : _draggable(data: _DragData.file(item), label: label, child: row),
      if (moving)
        Padding(
          padding: EdgeInsets.only(left: 10.0 + depth * 14 + 8, right: 8, bottom: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _moveOption('루트로 이동', 0, () {
              widget.onMoveItem(item, '');
              setState(() => movingItemId = null);
            }, muted: true),
            for (final (f, d) in flatFolders())
              _moveOption(baseName(f), d, () {
                widget.onMoveItem(item, f);
                setState(() => movingItemId = null);
              }),
          ]),
        ),
    ]);
  }

  Widget _moveOption(String label, int depth, VoidCallback onTap, {bool muted = false}) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.only(left: 8.0 + depth * 10, right: 8, top: 3, bottom: 3),
          decoration: BoxDecoration(
            color: c.bgSidebar,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label, style: TextStyle(fontSize: 11, color: muted ? c.textMuted : c.text)),
        ),
      ),
    );
  }

  List<Widget> _folderRows(String path, int depth, Map<String, List<Item>> folderFiles, Map<String, int> dawnNumbers) {
    final c = context.c;
    final selected = widget.selectedFolder == path;
    final files = folderFiles[path] ?? [];
    final children = childrenOf(path);
    final open = expanded.contains(path);
    final hasContent = children.isNotEmpty || files.isNotEmpty;
    final isDrop = dragging && dropTarget == path;

    final row = DragTarget<_DragData>(
      onWillAcceptWithDetails: (d) {
        final data = d.data;
        if (data.isFolder && (data.folderPath == path || path.startsWith('${data.folderPath}/'))) return false;
        setState(() => dropTarget = path);
        return true;
      },
      onLeave: (_) => setState(() => dropTarget = null),
      onAcceptWithDetails: (d) {
        _onDrop(d.data, path);
        setState(() => dropTarget = null);
      },
      builder: (context, _, _) => InkWell(
        onTap: () {
          setState(() => open ? expanded.remove(path) : expanded.add(path));
          widget.onFolderSelect(path);
        },
        onDoubleTap: () => setState(() {
          editingFolder = path;
          editCtrl.text = baseName(path);
        }),
        child: Container(
          padding: EdgeInsets.only(left: 10.0 + depth * 14, right: 8, top: 4, bottom: 4),
          decoration: BoxDecoration(
            color: (isDrop || selected) ? c.accentLight : Colors.transparent,
            border: Border(left: BorderSide(color: (isDrop || selected) ? c.accent : Colors.transparent, width: 2)),
          ),
          foregroundDecoration: isDrop ? BoxDecoration(border: Border.all(color: c.accent)) : null,
          child: Row(children: [
            AnimatedRotation(
              turns: open ? 0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: Opacity(
                opacity: hasContent ? 0.7 : 0.2,
                child: Icon(Icons.play_arrow, size: 10, color: c.textMuted), // 웹의 ▶ (글꼴에 없는 기호라 아이콘으로)
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: editingFolder == path
                  ? CallbackShortcutsEsc(
                      onEsc: () => setState(() => editingFolder = null),
                      child: Focus(
                        onFocusChange: (f) {
                          if (!f && editingFolder == path) commitRename();
                        },
                        child: TextField(
                          controller: editCtrl,
                          autofocus: true,
                          onSubmitted: (_) => commitRename(),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.text),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: c.bg,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: BorderSide(color: c.accent)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: BorderSide(color: c.accent)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: BorderSide(color: c.accent)),
                          ),
                        ),
                      ),
                    )
                  : Text(
                      baseName(path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: (selected || isDrop) ? c.accent : c.textHeading,
                      ),
                    ),
            ),
            if (files.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Opacity(opacity: 0.6, child: Text('${files.length}', style: TextStyle(fontSize: 10, color: c.textMuted))),
              ),
            _ghost('×', () => widget.onDeleteFolder(path)),
          ]),
        ),
      ),
    );

    return [
      _draggable(data: _DragData.folder(path), label: baseName(path), child: row),
      if (open) ...[
        for (final child in children) ..._folderRows(child, depth + 1, folderFiles, dawnNumbers),
        for (final item in sortItems(files)) _fileRow(item, depth + 1, dawnNumbers),
        if (!hasContent)
          Padding(
            padding: EdgeInsets.only(left: 10.0 + (depth + 1) * 14, top: 3, bottom: 3),
            child: Opacity(opacity: 0.5, child: Text('비어 있음', style: TextStyle(fontSize: 11, color: c.textMuted))),
          ),
      ],
    ];
  }
}

/// Esc 키를 누르면 onEsc 실행 (웹의 onKeyDown Escape 대응)
class CallbackShortcutsEsc extends StatelessWidget {
  final VoidCallback onEsc;
  final Widget child;
  const CallbackShortcutsEsc({super.key, required this.onEsc, required this.child});

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): onEsc},
        child: child,
      );
}
