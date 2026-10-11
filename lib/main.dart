import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'data/session.dart';
import 'presentation/controller.dart';
import 'presentation/screens.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Для этой сборки не настроено подключение Supabase. Соберите APK с SUPABASE_URL и SUPABASE_ANON_KEY по инструкции README.',
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseKey,
    authOptions: const FlutterAuthClientOptions(
      localStorage: SecureSessionStorage(),
    ),
  );
  runApp(const ProviderScope(child: CalorieDiaryApp()));
}

class CalorieDiaryApp extends ConsumerStatefulWidget {
  const CalorieDiaryApp({super.key});
  @override
  ConsumerState<CalorieDiaryApp> createState() => _CalorieDiaryAppState();
}

class _CalorieDiaryAppState extends ConsumerState<CalorieDiaryApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scheduleMicrotask(() => ref.read(diaryProvider).initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(diaryProvider).sync?.run());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(diaryProvider);
    return MaterialApp(
      title: 'Calorie Diary',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: diaryTheme(Brightness.light),
      darkTheme: diaryTheme(Brightness.dark),
      themeMode: switch (c.theme) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      },
      home: c.loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : c.failure != null
          ? Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(c.failure!),
                    TextButton(
                      onPressed: c.initialize,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            )
          : c.userId == null || c.needsPassword
          ? const AuthScreen()
          : const HomeScreen(),
    );
  }
}

ThemeData diaryTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF56DCC6),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xFF56DCC6) : const Color(0xFF006B5D),
        surface: dark ? const Color(0xFF242928) : Colors.white,
        onSurface: dark ? const Color(0xFFF3F7F7) : const Color(0xFF172225),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF151B1A)
        : const Color(0xFFF5F8F8),
    appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: dark ? const Color(0xFF535C5B) : const Color(0xFFCFDBD8),
          width: 1.5,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
      titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    ),
  );
}
