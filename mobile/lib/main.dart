import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'auth_page.dart';
import 'home_page.dart';
import 'ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AttendlyApp(api: Api()..restore()));
}

class AttendlyApp extends StatelessWidget {
  final Api api;
  const AttendlyApp({required this.api, super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Attendly · Điểm danh sinh viên',
    locale: const Locale('vi'),
    supportedLocales: const [Locale('vi'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: teal, primary: teal),
      scaffoldBackgroundColor: const Color(0xfff8fafc),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfff8fafc),
        foregroundColor: navy,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xffe2e8f0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xffe2e8f0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: teal, width: 1.8),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: teal,
          foregroundColor: Colors.white,
          elevation: 1,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xffe2e8f0)),
        ),
      ),
    ),
    home: ListenableBuilder(
      listenable: api,
      builder: (_, _) => !api.restored
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : api.user == null
          ? AuthPage(api: api)
          : HomePage(key: ValueKey(api.user!['id']), api: api),
    ),
  );
}
