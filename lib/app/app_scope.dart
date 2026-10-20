import 'package:finan/app/app_session.dart';
import 'package:finan/app/dependency_injection.dart';
import 'package:flutter/material.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    required this.graph,
    required this.session,
    required super.child,
    super.key,
  });

  final AppGraph graph;
  final AppSession session;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope não encontrado');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) {
    return graph != oldWidget.graph || session != oldWidget.session;
  }
}
