import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app.dart';
import 'config/constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox(AppConstants.settingsBox);
  await Hive.openBox(AppConstants.sessionBox);
  await Hive.openBox(AppConstants.offlineBox);
  await Hive.openBox(AppConstants.catalogCacheBox);

  runApp(const ProviderScope(child: NullFeedApp()));
}
