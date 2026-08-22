import 'package:flutter/material.dart';

class OpenFile {
  final String uri;
  final String name;
  String content;
  bool isDirty;

  OpenFile({
    required this.uri,
    required this.name,
    required this.content,
    this.isDirty = false,
  });
}

class OpenFilesModel extends ChangeNotifier {
  final List<OpenFile> files = [];
  int activeIndex = -1;

  OpenFile? get active => activeIndex >= 0 && activeIndex < files.length
      ? files[activeIndex]
      : null;

  void open(OpenFile file) {
    final existing = files.indexWhere((f) => f.uri == file.uri);
    if (existing >= 0) {
      // Файл мог измениться на диске после открытия вкладки — обновляем
      // содержимое свежепрочитанным. Несохранённые правки не трогаем.
      final old = files[existing];
      if (!old.isDirty && file.content != old.content) {
        old.content = file.content;
      }
      activeIndex = existing;
    } else {
      files.add(file);
      activeIndex = files.length - 1;
    }
    notifyListeners();
  }

  void close(int index) {
    files.removeAt(index);
    if (activeIndex >= files.length) activeIndex = files.length - 1;
    notifyListeners();
  }

  void setActive(int index) {
    activeIndex = index;
    notifyListeners();
  }

  void markDirty(String uri) {
    final idx = files.indexWhere((f) => f.uri == uri);
    if (idx < 0) return;
    files[idx].isDirty = true;
    notifyListeners();
  }

  void markClean(String uri) {
    final idx = files.indexWhere((f) => f.uri == uri);
    if (idx >= 0) files[idx].isDirty = false;
    notifyListeners();
  }
}
