import 'package:flutter/material.dart';

/// 输入法是否真的开着。切到别的 App 再回来时，OEM 经常留下 stale `viewInsets`，
/// 底栏会一直藏着。必须同时看到焦点还在输入框上。
bool isSoftwareKeyboardVisible(BuildContext context) {
  if (MediaQuery.viewInsetsOf(context).bottom <= 0) return false;
  return focusIsTextInput();
}

bool focusIsTextInput() {
  final node = FocusManager.instance.primaryFocus;
  if (node == null || !node.hasFocus) return false;
  // 路由 FocusScope 几乎永远 hasFocus，子孙里一定能扫到某个 TextField。
  // 把它当成「正在打字」会在 OEM 留下假 viewInsets 时把整页挤扁。
  if (node is FocusScopeNode) return false;
  if (_contextIsTextInput(node.context)) return true;
  for (final child in node.descendants) {
    if (_contextIsTextInput(child.context)) return true;
  }
  return false;
}

bool _contextIsTextInput(BuildContext? context) {
  if (context == null) return false;
  final widget = context.widget;
  if (widget is EditableText ||
      widget is TextField ||
      widget is TextFormField ||
      widget is SearchBar) {
    return true;
  }
  return context.findAncestorWidgetOfExactType<EditableText>() != null ||
      context.findAncestorWidgetOfExactType<TextField>() != null ||
      context.findAncestorWidgetOfExactType<SearchBar>() != null;
}
