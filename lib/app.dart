import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config/app_globals.dart';
import 'config/theme.dart';
import 'config/routes.dart';

class NullFeedApp extends ConsumerWidget {
  const NullFeedApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'NullFeed',
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: NullFeedTheme.darkTheme,
      darkTheme: NullFeedTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // Honor the platform Dynamic Type setting, but clamp the extremes so the
      // fixed-size cards and rows don't break at very large accessibility sizes.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 0.8,
              maxScaleFactor: 1.3,
            ),
          ),
          child: child!,
        );
      },
    );
  }
}
