// 파일 내려받기·고르기 — 웹은 브라우저 다운로드, 네이티브는 저장 창
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'file_io_stub.dart' if (dart.library.js_interop) 'file_io_web.dart' as impl;

/// 글 파일 저장 — 성공하면 true
Future<bool> saveTextFile(String fileName, String text) async {
  final bytes = Uint8List.fromList(utf8.encode(text));
  if (impl.isWeb) {
    impl.downloadBytes(fileName, bytes);
    return true;
  }
  final uri = await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: 'application/json');
  return uri != null;
}

/// .json 파일 하나 고르기 — 내용 글 (취소하면 null)
Future<String?> pickJsonFile() async {
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
  if (file == null) return null;
  return utf8.decode(await file.readAsBytes());
}
