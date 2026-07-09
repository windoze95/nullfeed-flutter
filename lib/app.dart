import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config/app_globals.dart';
import 'config/theme.dart';
import 'config/routes.dart';
import 'providers/auth_provider.dart';
import 'providers/feed_provider.dart';

class NullFeedApp extends ConsumerStatefulWidget {
  const NullFeedApp({super.key});

  @override
  ConsumerState<NullFeedApp> createState() => _NullFeedAppState();
}

class _NullFeedAppState extends ConsumerState<NullFeedApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On returning to the foreground, refresh the feed so watch positions
    // changed elsewhere (notably on another device) surface — the Continue
    // Watching row in particular. Skipped when signed out: nothing watches the
    // feed then, and the refetch would just 401.
    if (state == AppLifecycleState.resumed &&
        ref.read(authStateProvider).currentUser != null) {
      invalidateFeedProviders(ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'NullFeed',
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: NullFeedTheme.darkTheme,
      darkTheme: NullFeedTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // Honor accessibility text sizes up to 200%. Content cards clamp their
      // own labels and primary screens scroll, so readability wins over a
      // tightly frozen layout.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 0.9,
              maxScaleFactor: 2.0,
            ),
          ),
          child: child!,
        );
      },
    );
  }
}
