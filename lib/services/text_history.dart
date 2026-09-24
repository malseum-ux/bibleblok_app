// 되돌리기·다시하기 기록 — 웹 StepView.jsx 의 useTextHistory 와 같은 규칙
// 입력이 0.8초 멈추면 한 단계로 기록하고, 최대 100단계까지 보관한다.
import 'dart:async';

import 'package:flutter/foundation.dart';

class TextHistory extends ChangeNotifier {
  String _text;
  List<String> _snapshots;
  int _idx = 0;
  Timer? _timer;

  TextHistory(String initial)
      : _text = initial,
        _snapshots = [initial];

  String get text => _text;
  bool get canUndo => _idx > 0 || _text != _snapshots[_idx];
  bool get canRedo => _idx < _snapshots.length - 1;

  void _push(String val) {
    _snapshots = _snapshots.sublist(0, _idx + 1);
    if (_snapshots.last != val) {
      _snapshots.add(val);
      if (_snapshots.length > 100) _snapshots.removeAt(0);
    }
    _idx = _snapshots.length - 1;
    notifyListeners();
  }

  void onChange(String newText) {
    _text = newText;
    notifyListeners();
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 800), () => _push(newText));
  }

  void reset(String value) {
    _timer?.cancel();
    _text = value;
    _snapshots = [value];
    _idx = 0;
    notifyListeners();
  }

  void undo() {
    _timer?.cancel();
    if (_text != _snapshots[_idx]) {
      _snapshots = _snapshots.sublist(0, _idx + 1)..add(_text);
      _idx = _snapshots.length - 1;
    }
    if (_idx > 0) {
      _idx--;
      _text = _snapshots[_idx];
    }
    notifyListeners();
  }

  void redo() {
    _timer?.cancel();
    if (_idx < _snapshots.length - 1) {
      _idx++;
      _text = _snapshots[_idx];
      notifyListeners();
    }
  }

  void forceSnapshot() {
    _timer?.cancel();
    _push(_text);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
