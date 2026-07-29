import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'app/theme.dart';
import 'models/open_file.dart';
import 'models/settings_model.dart';
import 'services/file_service.dart';
import 'services/language_install_service.dart';
import 'services/language_service.dart';
import 'services/settings_service.dart';
import 'screens/editor_screen.dart';

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
      home: const EditorScreen(),
    );
  }
}
