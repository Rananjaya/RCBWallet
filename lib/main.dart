import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wallet/models/app_lock_provider.dart';
import 'package:wallet/models/reminder_settings_provider.dart';
import 'package:wallet/models/theme_provider.dart';
import 'package:wallet/models/startup_settings_provider.dart';
import 'package:wallet/services/app_initialization_service.dart';
import 'package:wallet/services/encryption_service.dart';
import 'models/auto_backup_provider.dart';
import 'models/provider_helper.dart';
import 'screens/homescreen.dart';
import 'package:provider/provider.dart';
import 'package:wallet/services/auto_backup_service.dart';
import 'package:wallet/widgets/app_lock_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeProvider = ThemeProvider();
  final startupProvider = StartupSettingsProvider();
  final autoBackupProvider = AutoBackupProvider();
  final reminderSettingsProvider = ReminderSettingsProvider();

  await Future.wait([
    themeProvider.init(),
    startupProvider.loadStartupSettings(),
    autoBackupProvider.init(),
    reminderSettingsProvider.init(),
    AppInitializationService.initializeApp(),
  ]);

  AutoBackupService.initialize(autoBackupProvider);

  // Starts locked when the app lock is enabled in Settings.
  final appLockProvider = AppLockProvider(startupProvider);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => WalletProvider()),
        ChangeNotifierProvider(create: (context) => PassProvider()),
        ChangeNotifierProvider(create: (context) => IdentityProvider()),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: startupProvider),
        ChangeNotifierProvider.value(value: autoBackupProvider),
        ChangeNotifierProvider.value(value: appLockProvider),
        ChangeNotifierProvider.value(value: reminderSettingsProvider),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.paused) {
          EncryptionService.instance.clearImageCache();
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Selector<ThemeProvider, ({ThemeMode themeMode, bool useSystemFont})>(
      selector: (_, provider) => (
        themeMode: provider.currentTheme,
        useSystemFont: provider.useSystemFont,
      ),
      builder: (context, data, _) {
        final themeProvider = Provider.of<ThemeProvider>(
          context,
          listen: false,
        );
        return MaterialApp(
          title: 'RCBWallet',
          debugShowCheckedModeBanner: false,
          theme: themeProvider.lightTheme,
          darkTheme: themeProvider.darkTheme,
          themeMode: data.themeMode,
          home: const SplashScreen(),
          builder: (context, child) =>
              AppLockGate(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _iconSlideAnimation;
  AppLockProvider? _appLock;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _iconSlideAnimation = Tween<double>(begin: 20.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.1, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    _animationController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preCacheAssets();
      _checkStartupSettings();
    });
  }

  void _preCacheAssets() {
    final networks = ['visa', 'mastercard', 'amex', 'discover', 'rupay'];
    for (final network in networks) {
      precacheImage(AssetImage('assets/network/$network.png'), context);
    }
  }

  @override
  void dispose() {
    _appLock?.removeListener(_onLockChanged);
    _animationController.dispose();
    super.dispose();
  }

  /// Opens the home screen once the app is unlocked. Authentication itself
  /// is handled by [AppLockGate], which covers this screen while locked.
  void _checkStartupSettings() {
    final appLock = context.read<AppLockProvider>();
    if (!appLock.isLocked) {
      _navigateToHomeScreen();
      return;
    }
    _appLock = appLock..addListener(_onLockChanged);
  }

  void _onLockChanged() {
    final appLock = _appLock;
    if (appLock != null && !appLock.isLocked) {
      appLock.removeListener(_onLockChanged);
      _appLock = null;
      _navigateToHomeScreen();
    }
  }

  void _navigateToHomeScreen() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const HomeScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return child;
          },
          transitionDuration: Duration.zero,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black;

    SystemChrome.setSystemUIOverlayStyle(
      isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    );

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Transform.translate(
                      offset: Offset(0, _iconSlideAnimation.value),
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          color: isDark
                              ? const Color(0xFF1A1A1A)
                              : const Color(0xFFF0F0F0),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF2A2A2A)
                                : const Color(0xFFE0E0E0),
                            width: 0.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: textColor.withValues(alpha: 0.08),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.wallet_rounded,
                            size: 56,
                            color: textColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.translate(
                    offset: Offset(0, _iconSlideAnimation.value * 1.2),
                    child: Column(
                      children: [
                        Text(
                          'RCBWALLET',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                            letterSpacing: 8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Secure • Simple • Smart',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white54 : Colors.black45,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.translate(
                    offset: Offset(0, _iconSlideAnimation.value * 1.5),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark
                            ? const Color(0xFF1A1A1A)
                            : const Color(0xFFF5F5F5),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
