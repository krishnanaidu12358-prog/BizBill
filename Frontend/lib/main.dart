import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_config.dart';
import 'core/theme.dart';
import 'screens/admin/admin_shell.dart';
import 'screens/auth/login_screen.dart';
import 'screens/customer/customer_shell.dart';
import 'screens/owner/owner_shell.dart';
import 'screens/worker/worker_shell.dart';
import 'services/branding_images.dart';
import 'state/appearance.dart';
import 'state/session.dart';
import 'widgets/brand_logo.dart';
import 'widgets/coin_loader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();

  final appearance = Appearance();
  await appearance.load();

  final session = Session(appearance: appearance);
  BrandingImages.api = session.api;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: appearance),
      ],
      child: const BizFlowApp(),
    ),
  );

  await session.restore();
}

class BizFlowApp extends StatelessWidget {
  const BizFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<Appearance>();

    return MaterialApp(
      title: 'BizBill',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, paletteKey: appearance.palette),
      darkTheme: buildTheme(Brightness.dark, paletteKey: appearance.palette),
      themeMode: appearance.mode,
      home: const RootRouter(),
    );
  }
}

/// Sends each account to the right home screen.
class RootRouter extends StatelessWidget {
  const RootRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();

    if (session.isRestoring) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandLogo(height: 190),
              const SizedBox(height: 28),
              CoinLoader(size: 56),
            ],
          ),
        ),
      );
    }

    if (!session.isLoggedIn) return const LoginScreen();

    switch (session.user!.role) {
      case 'SuperAdmin':
        return const AdminShell();
      case 'BusinessUser':
        return const OwnerShell();
      case 'Customer':
        return const CustomerShell();
      case 'Worker':
        return const WorkerShell();
      default:
        return const LoginScreen();
    }
  }
}
