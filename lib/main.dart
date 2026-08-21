import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'app/theme.dart';
import 'models/open_file.dart';
import 'models/settings_model.dart';
import 'models/update_model.dart';
import 'screens/hard_update_screen.dart';
import 'services/file_service.dart';
import 'services/language_install_service.dart';
import 'services/language_service.dart';
import 'services/settings_service.dart';
import 'screens/editor_screen.dart';
import 'screens/user_agreement_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Bootstrap storage layout before anything tries to read it.
  await FileService.ensureLayout();
  final settings = SettingsService.instance;
  await settings.init();
  final language = LanguageService(settings);
  await language.init();
  final installer = LanguageInstallService.instance;
  await installer.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsModel(settings)),
        ChangeNotifierProvider.value(value: language),
        ChangeNotifierProvider.value(value: installer),
        ChangeNotifierProvider(create: (_) => OpenFilesModel()),
        ChangeNotifierProvider(create: (_) => UpdateModel()),
      ],
      child: const XunCodeApp(),
    ),
  );
}

class XunCodeApp extends StatelessWidget {
  const XunCodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    final language = context.watch<LanguageService>();
    return MaterialApp(
      title: 'XunCode',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: VscodeTheme.dark(),
      themeMode: settings.themeMode,
      locale: language.locale,
      supportedLocales: const [Locale('en'), Locale('ru')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _UpdateGate(child: EditorScreen()),
    );
  }
}

/// Входная точка UI: сначала пользовательское соглашение (один раз),
/// затем фоновая проверка обновлений и, при критическом релизе для
/// платформы пользователя, экран тотальной блокировки поверх IDE.
class _UpdateGate extends StatefulWidget {
  final Widget child;

  const _UpdateGate({required this.child});

  @override
  State<_UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<_UpdateGate> {
  @override
  void initState() {
    super.initState();
    // Даём IDE открыться мгновенно; проверка идёт в фоне.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!_accepted) return; // проверка запустится после принятия
      await _runUpdateCheck();
    });
  }

  bool get _accepted => SettingsService.instance.agreementAccepted;

  Future<void> _runUpdateCheck() async {
    final model = context.read<UpdateModel>();
    await model.check();
    _maybeShowHardBlock(model);
  }

  void _onAgreementAccepted() {
    SettingsService.instance.setAgreementAccepted(true).then((_) {
      if (!mounted) return;
      setState(() {});
      // Пользователь внутри IDE — теперь можно проверить обновления.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runUpdateCheck();
      });
    });
  }

  void _maybeShowHardBlock(UpdateModel model) {
    if (!model.needsHardBlock || model.hardShown) return;
    final result = model.result;
    if (result == null) return;
    model.markHardShown();
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => HardUpdateScreen(result: result),
        transitionDuration: const Duration(milliseconds: 250),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_accepted) {
      return UserAgreementScreen(
        firstLaunch: true,
        onAccepted: _onAgreementAccepted,
      );
    }
    return widget.child;
  }
}
