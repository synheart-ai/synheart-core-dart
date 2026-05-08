import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:synheart_core/synheart_core.dart';
import 'lib/providers/synheart_provider.dart';
import 'lib/screens/home_screen.dart';
import 'lib/screens/consent_screen.dart';

void main() {
  runApp(const SynheartExampleApp());
}

class SynheartExampleApp extends StatelessWidget {
  const SynheartExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SynheartProvider(),
      child: Consumer<SynheartProvider>(
        builder: (context, provider, child) {
          // Build the MaterialApp
          final materialApp = MaterialApp(
            title: 'Synheart SDK Demo',
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF6366F1), // Indigo
                brightness: Brightness.light,
              ),
              useMaterial3: true,
              cardTheme: CardThemeData(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            home: const _AppNavigator(),
            routes: {'/consent': (context) => const ConsentScreen()},
            debugShowCheckedModeBanner: false,
          );

          // Wrap with behavior gesture detector (SDK handles consent check internally)
          return Synheart.wrapWithBehaviorDetector(materialApp);
        },
      ),
    );
  }
}

/// Navigator that shows consent screen if needed, otherwise home screen
class _AppNavigator extends StatefulWidget {
  const _AppNavigator();

  @override
  State<_AppNavigator> createState() => _AppNavigatorState();
}

class _AppNavigatorState extends State<_AppNavigator> {
  bool _hasNavigatedToConsent = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<SynheartProvider>(
      builder: (context, provider, child) {
        // If SDK is initialized and consent is needed, show consent screen
        // Only navigate once to avoid conflicts
        if (provider.isInitialized &&
            provider.needsConsent &&
            !_hasNavigatedToConsent) {
          // Use a post-frame callback to navigate after build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                context.mounted &&
                Navigator.of(context).canPop() == false) {
              _hasNavigatedToConsent = true;
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ConsentScreen()));
            }
          });
        } else if (!provider.needsConsent) {
          // Reset flag when consent is no longer needed
          _hasNavigatedToConsent = false;
        }

        return const HomeScreen();
      },
    );
  }
}
