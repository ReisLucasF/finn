import 'package:finan/app/app.dart';
import 'package:finan/app/dependency_injection.dart';
import 'package:flutter/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(FinanApp(graph: AppGraph.production()));
}
