import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:utaha_authenticator/app/app.dart';

/// Application entry point.
///
/// The app is entirely offline and has no background work, so there is nothing
/// to initialise beyond the Flutter bindings before showing the first frame.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: UtahaApp()));
}
