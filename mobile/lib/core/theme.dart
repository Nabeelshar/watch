import 'package:flutter/material.dart';

ThemeData afterglowTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme:
      ColorScheme.fromSeed(
        seedColor: const Color(0xffb99aee),
        brightness: Brightness.dark,
      ).copyWith(
        primary: const Color(0xffb99aee),
        surface: const Color(0xff16161b),
        onSurface: const Color(0xffefedf3),
        onSurfaceVariant: const Color(0xffb8b3c2),
        surfaceContainerHighest: const Color(0xff29282f),
      ),
  scaffoldBackgroundColor: const Color(0xff16161b),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xff16161b),
    surfaceTintColor: Colors.transparent,
    centerTitle: false,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xff24242b),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
  ),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Color(0xff1c1c22),
    indicatorColor: Color(0xff393046),
  ),
  dividerTheme: const DividerThemeData(color: Color(0xff303038), thickness: 1),
);
