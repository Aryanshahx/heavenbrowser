import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heavenbrowser/app.dart';
import 'package:heavenbrowser/core/constants/app_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Renders Heaven Browser build configuration accurately', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const HeavenBrowserApp());

    expect(find.text(AppConstants.appName), findsAtLeastNWidgets(1));
    expect(find.text(AppConstants.appVersion), findsOneWidget);
    expect(find.text(AppConstants.packageName), findsOneWidget);
  });

  testWidgets('Switches MaterialApp theme mode between Dark, Light, and System', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const HeavenBrowserApp());

    MaterialApp app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(find.text('Active brightness: Dark'), findsOneWidget);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.light);
    expect(find.text('Active brightness: Light'), findsOneWidget);
  });

  testWidgets('Copies real build info to system clipboard and shows snackbar', (
    WidgetTester tester,
  ) async {
    String? copiedText;

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final Map<dynamic, dynamic> args =
              methodCall.arguments as Map<dynamic, dynamic>;
          copiedText = args['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(const HeavenBrowserApp());

    final Finder copyButton = find.text('Copy Build Info');
    await tester.scrollUntilVisible(
      copyButton,
      200.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(copyButton);
    await tester.pumpAndSettle();

    expect(copiedText, isNotNull);
    expect(copiedText, contains('App: Heaven Browser'));
    expect(copiedText, contains('Version: 0.0.1'));
    expect(copiedText, contains('Package: com.hypertechlabs.heavenbrowser'));
    expect(find.text('Build info copied to clipboard'), findsOneWidget);
  });
}
