import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config/theme.dart';
import 'config/routes.dart';
import 'widgets/adaptive_layout.dart';

class NullFeedApp extends ConsumerWidget {
  const NullFeedApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
      },
      child: MaterialApp.router(
        title: 'NullFeed',
        theme: NullFeedTheme.darkTheme,
        darkTheme: NullFeedTheme.darkTheme,
        themeMode: ThemeMode.dark,
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          if (AdaptiveLayout.isTv(context)) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.3),
              ),
              child: child!,
            );
          }
          return child!;
        },
      ),
    );
  }
}
