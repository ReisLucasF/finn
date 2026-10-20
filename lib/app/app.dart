import 'package:finan/app/app_config.dart';
import 'package:finan/app/app_scope.dart';
import 'package:finan/app/app_session.dart';
import 'package:finan/app/dependency_injection.dart';
import 'package:finan/core/theme/app_theme.dart';
import 'package:finan/core/theme/theme_controller.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:finan/presentation/onboarding/onboarding_screen.dart';
import 'package:finan/presentation/shared/feedback_widgets.dart';
import 'package:finan/presentation/shell/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class FinanApp extends StatefulWidget {
  const FinanApp({required this.graph, super.key});

  final AppGraph graph;

  @override
  State<FinanApp> createState() => _FinanAppState();
}

class _FinanAppState extends State<FinanApp> {
  final _theme = ThemeController();
  AppSession? _session;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _theme.addListener(_onTheme);
    _theme.load();
    _boot();
  }

  void _onTheme() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _theme.removeListener(_onTheme);
    _theme.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final alreadyLoading = _loading && _error == null;
    if (mounted && !alreadyLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final user = await widget.graph.open();
      final session = _session;
      if (session == null) {
        _session = AppSession(user);
      } else {
        session.setUser(user);
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return ThemeScope(
      controller: _theme,
      child: MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _theme.mode,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        if (_error != null) {
          return Scaffold(
            body: ErrorView(message: friendlyError(_error!), onRetry: _boot),
          );
        }
        if (_loading || session == null) return const LoadingSkeleton();
        return AppScope(
          graph: widget.graph,
          session: session,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const _AppHome(),
    ),
    );
  }
}

class _AppHome extends StatelessWidget {
  const _AppHome();

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (session.user.needsOnboarding) return const OnboardingScreen();
        return const HomeShell();
      },
    );
  }
}
