// 글 형식 변환 — 저장은 웹과 같은 HTML(또는 일반 글), 화면에서는 Quill 문서로 다룬다
//
// 웹의 AI 결과는 처음엔 일반 글(줄바꿈)이고, 편집하면 TipTap 이 만든 HTML 이 된다.
//   <p style="text-align: center">…</p>, <strong>, <em>, <u>, <s>,
//   <span style="color: #dc2626">, <span style="font-size: 1.2em">, <h1~3>, <ul/ol><li><p>, <blockquote>, <br>
// 이 형식을 직접 읽고 쓴다 (범용 변환 패키지는 문단 사이 줄바꿈을 빠뜨려서 쓰지 않는다).
// 글자 크기: 편집기 안에서는 px 숫자로만 다룰 수 있어, em 은 기본 14px 기준으로 바꿔 읽고 저장할 때 되돌린다.
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

const _baseFontPx = 14.0;

bool isHtml(String? s) => s != null && s.trimLeft().startsWith('<');

/// 웹 stripHtml — HTML 이면 글자만, 아니면 그대로
String stripHtml(String? source) {
  if (source == null) return '';
  if (!isHtml(source)) return source;
  return docFromSource(source).toPlainText().trimRight();
}

/// 저장된 글 → Quill 문서
Document docFromSource(String? source) {
  if (source == null || source.trim().isEmpty) return Document();
  if (isHtml(source)) return Document.fromDelta(htmlToDelta(source));
  // 일반 글 — 웹 보기 화면처럼 빈 줄을 빼고 줄마다 문단으로
  final lines = source.split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (lines.isEmpty) return Document();
  return Document.fromDelta(Delta()..insert('${lines.join('\n')}\n'));
}

/// Quill 문서 → 저장할 HTML
String htmlFromDoc(Document doc) => deltaToHtml(doc.toDelta());

/// 일반 글 줄들을 문단 HTML 로 (웹 applyToSermon 과 같은 방식)
String linesToHtml(String text) =>
    text.split('\n').where((l) => l.trim().isNotEmpty).map((l) => '<p>${escapeHtml(l)}</p>').join();

String escapeHtml(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

// ── HTML → Delta ─────────────────────────────────────────────────────────────

Map<String, String> _styleMap(dom.Element el) {
  final out = <String, String>{};
  for (final part in (el.attributes['style'] ?? '').split(';')) {
    final i = part.indexOf(':');
    if (i < 0) continue;
    out[part.substring(0, i).trim().toLowerCase()] = part.substring(i + 1).trim();
  }
  return out;
}

double? _sizeToPx(String v) {
  final s = v.trim().toLowerCase();
  if (s.endsWith('em')) {
    final n = double.tryParse(s.substring(0, s.length - (s.endsWith('rem') ? 3 : 2)));
    return n == null ? null : n * _baseFontPx;
  }
  if (s.endsWith('px')) return double.tryParse(s.substring(0, s.length - 2));
  return double.tryParse(s);
}

Delta htmlToDelta(String html) {
  final delta = Delta();
  final fragment = html_parser.parseFragment(html);
  var lineOpen = false; // 줄이 열려 있는지 (마지막에 줄바꿈이 필요한지)

  void text(String t, Map<String, dynamic> attrs) {
    if (t.isEmpty) return;
    delta.insert(t, attrs.isEmpty ? null : Map<String, dynamic>.from(attrs));
    lineOpen = true;
  }

  void newline(Map<String, dynamic> blockAttrs) {
    delta.insert('\n', blockAttrs.isEmpty ? null : Map<String, dynamic>.from(blockAttrs));
    lineOpen = false;
  }

  void inline(dom.Node node, Map<String, dynamic> attrs, Map<String, dynamic> blockAttrs) {
    if (node is dom.Text) {
      text(node.text.replaceAll(RegExp(r'[\r\n]+'), ' '), attrs);
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName;
    if (tag == 'br') {
      newline(blockAttrs);
      return;
    }
    final next = Map<String, dynamic>.from(attrs);
    switch (tag) {
      case 'strong' || 'b':
        next['bold'] = true;
      case 'em' || 'i':
        next['italic'] = true;
      case 'u':
        next['underline'] = true;
      case 's' || 'strike' || 'del':
        next['strike'] = true;
      case 'code':
        next['code'] = true;
    }
    final style = _styleMap(node);
    if (style['color'] != null) next['color'] = style['color'];
    if (style['font-size'] != null) {
      final px = _sizeToPx(style['font-size']!);
      if (px != null) next['size'] = px;
    }
    if (style['font-weight'] == 'bold' || style['font-weight'] == '700') next['bold'] = true;
    for (final child in node.nodes) {
      inline(child, next, blockAttrs);
    }
  }

  void block(dom.Node node, Map<String, dynamic> inherited) {
    if (node is dom.Text) {
      if (node.text.trim().isEmpty) return;
      text(node.text.replaceAll(RegExp(r'[\r\n]+'), ' '), const {});
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName;
    final style = _styleMap(node);
    final blockAttrs = Map<String, dynamic>.from(inherited);
    final align = style['text-align'];
    if (align != null && align != 'left' && align != 'start') blockAttrs['align'] = align;

    switch (tag) {
      case 'ul' || 'ol':
        for (final li in node.children) {
          block(li, {...inherited, 'list': tag == 'ul' ? 'bullet' : 'ordered'});
        }
        return;
      case 'blockquote':
        for (final child in node.nodes) {
          block(child, {...blockAttrs, 'blockquote': true});
        }
        if (lineOpen) newline({...blockAttrs, 'blockquote': true});
        return;
      case 'li':
        // TipTap 목록: <li><p>…</p></li>
        final paras = node.children.where((c) => c.localName == 'p').toList();
        if (paras.isNotEmpty) {
          for (final p in paras) {
            for (final child in p.nodes) {
              inline(child, const {}, blockAttrs);
            }
            newline(blockAttrs);
          }
        } else {
          for (final child in node.nodes) {
            inline(child, const {}, blockAttrs);
          }
          newline(blockAttrs);
        }
        return;
      case 'hr':
        return;
      case 'p' || 'div' || 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        if (tag!.startsWith('h') && tag.length == 2) blockAttrs['header'] = int.parse(tag.substring(1)).clamp(1, 3);
        // 블록 안에 또 블록이 있으면 (div 안의 p 등) 그대로 풀어 쓴다
        final hasBlockChild = node.children.any((c) => const {'p', 'div', 'ul', 'ol', 'blockquote', 'h1', 'h2', 'h3'}.contains(c.localName));
        if (hasBlockChild) {
          for (final child in node.nodes) {
            block(child, inherited);
          }
          return;
        }
        for (final child in node.nodes) {
          inline(child, const {}, blockAttrs);
        }
        newline(blockAttrs);
        return;
      default:
        // 블록 밖 인라인 (strong 등) — 한 문단으로 모은다
        inline(node, const {}, const {});
    }
  }

  for (final node in fragment.nodes) {
    block(node, const {});
  }
  if (lineOpen || delta.isEmpty) newline(const {});
  return delta;
}

// ── Delta → HTML ─────────────────────────────────────────────────────────────

String _fmt(double v) {
  final s = v.toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

String _inlineHtml(String text, Map<String, dynamic>? a) {
  var out = escapeHtml(text);
  if (a == null || a.isEmpty) return out;
  if (a['code'] == true) out = '<code>$out</code>';
  if (a['strike'] == true) out = '<s>$out</s>';
  if (a['underline'] == true) out = '<u>$out</u>';
  if (a['italic'] == true) out = '<em>$out</em>';
  if (a['bold'] == true) out = '<strong>$out</strong>';
  final styles = <String>[];
  if (a['color'] is String) styles.add('color: ${a['color']}');
  final size = a['size'];
  if (size != null) {
    final px = size is num ? size.toDouble() : double.tryParse('$size');
    if (px != null) styles.add('font-size: ${_fmt(px / _baseFontPx)}em');
  }
  if (styles.isNotEmpty) out = '<span style="${styles.join('; ')}">$out</span>';
  return out;
}

String deltaToHtml(Delta delta) {
  final buf = StringBuffer();
  final line = StringBuffer();
  String? openList; // 'ul' | 'ol'

  void closeList() {
    if (openList != null) {
      buf.write('</$openList>');
      openList = null;
    }
  }

  void endLine(Map<String, dynamic>? attrs) {
    final a = attrs ?? const {};
    final inner = line.toString();
    line.clear();
    final align = a['align'];
    final styleAttr = align is String ? ' style="text-align: $align"' : '';
    final list = a['list'];
    if (list == 'bullet' || list == 'ordered') {
      final tag = list == 'bullet' ? 'ul' : 'ol';
      if (openList != tag) {
        closeList();
        buf.write('<$tag>');
        openList = tag;
      }
      buf.write('<li><p$styleAttr>$inner</p></li>');
      return;
    }
    closeList();
    final header = a['header'];
    final tag = header is int && header >= 1 && header <= 6 ? 'h$header' : 'p';
    final body = '<$tag$styleAttr>$inner</$tag>';
    buf.write(a['blockquote'] == true ? '<blockquote>$body</blockquote>' : body);
  }

  for (final op in delta.toList()) {
    final data = op.data;
    if (data is! String) continue; // 그림 등은 다루지 않는다
    final attrs = op.attributes;
    final parts = data.split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) line.write(_inlineHtml(parts[i], attrs));
      if (i < parts.length - 1) endLine(attrs);
    }
  }
  if (line.isNotEmpty) endLine(null);
  closeList();
  // 끝의 빈 문단은 뺀다 (Quill 문서는 항상 줄바꿈으로 끝난다)
  return buf.toString().replaceFirst(RegExp(r'(<p></p>)+$'), '');
}
