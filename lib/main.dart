import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/storage.dart';
import 'ui/menu_screen.dart';
import 'ui/pixel/pixel_assets.dart';
import 'ui/widgets.dart' show Pal, PixelTextScaler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Storage.init();
  } catch (e) {
    debugPrint('Storage unavailable, progress will not be saved: $e');
  }
  await PixelAssets.load();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const HexApp());
}

/// VT323 has tall default line metrics; tighten them.
const _tight = TextStyle(height: 1.05);

class HexApp extends StatelessWidget {
  const HexApp({super.key, this.home = const MenuScreen()});

  /// The first screen. Overridable so tests can open any screen directly.
  final Widget home;

  @override
  Widget build(BuildContext context) {
    const sharp = RoundedRectangleBorder();
    return MaterialApp(
      title: 'Hex Tactics',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: PixelTextScaler(mq.devicePixelRatio)),
          child: child!,
        );
      },
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'VT323',
        useMaterial3: true,
        textTheme: const TextTheme(
          bodyLarge: _tight,
          bodyMedium: _tight,
          bodySmall: _tight,
          titleLarge: _tight,
          titleMedium: _tight,
          titleSmall: _tight,
          labelLarge: _tight,
          labelMedium: _tight,
          labelSmall: _tight,
        ),
        colorScheme: const ColorScheme.dark(
          primary: Pal.gold,
          onPrimary: Pal.ink,
          surface: Pal.panel,
          onSurface: Pal.text,
          error: Pal.red,
        ),
        scaffoldBackgroundColor: Pal.bgTop,
        splashFactory: NoSplash.splashFactory,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _CutTransitions(),
            TargetPlatform.iOS: _CutTransitions(),
            TargetPlatform.macOS: _CutTransitions(),
            TargetPlatform.windows: _CutTransitions(),
            TargetPlatform.linux: _CutTransitions(),
          },
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Pal.panel,
          contentTextStyle: TextStyle(
            fontFamily: 'VT323',
            color: Pal.goldLight,
            fontSize: 16,
          ),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Pal.gold, width: 2),
          ),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Pal.panel,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Pal.gold, width: 2),
          ),
          titleTextStyle: TextStyle(
            fontFamily: 'VT323',
            color: Pal.gold,
            fontSize: 22,
          ),
          contentTextStyle: TextStyle(
            fontFamily: 'VT323',
            color: Pal.text,
            fontSize: 16,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            shape: sharp,
            foregroundColor: Pal.gold,
            textStyle: const TextStyle(fontFamily: 'VT323', fontSize: 17),
          ),
        ),
      ),
      home: home,
    );
  }
}

/// Screens cut in instantly: no fades or slides to blur the pixel grid.
class _CutTransitions extends PageTransitionsBuilder {
  const _CutTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
