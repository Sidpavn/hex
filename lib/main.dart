import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/storage.dart';
import 'ui/menu_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Storage.init();
  } catch (e) {
    debugPrint('Storage unavailable, progress will not be saved: $e');
  }
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const HexApp());
}

class HexApp extends StatelessWidget {
  const HexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Games',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFFE0A030),
        scaffoldBackgroundColor: const Color(0xFF12231F),
        useMaterial3: true,
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF0B1512),
          contentTextStyle: const TextStyle(color: Color(0xFFFFE082)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0x66FFE082)),
          ),
        ),
      ),
      home: const MenuScreen(),
    );
  }
}
