import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_ai/main.dart';

void main() {
  testWidgets('SovereignApp renders brand and empty state on initial launch', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SovereignApp());
    await tester.pumpAndSettle();

    expect(find.text('Sovereign AI'), findsOneWidget);
    expect(find.text('Local & Offline Intelligence'), findsOneWidget);
    expect(find.text('No Model Loaded'), findsWidgets);
  });

  testWidgets('Can navigate across all tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const SovereignApp());
    await tester.pumpAndSettle();

    // Navigate to Models
    await tester.tap(find.text('Models'));
    await tester.pumpAndSettle();
    expect(find.text('Model Manager'), findsOneWidget);
    expect(find.text('SmolLM2 135M Instruct'), findsOneWidget);

    // Navigate to History
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Chat History'), findsOneWidget);
    expect(find.text('No Conversations Yet'), findsOneWidget);

    // Navigate to Settings
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance & Theme'), findsOneWidget);

    // Switch theme to Light mode
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    // Navigate to About
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('About Sovereign AI'), findsOneWidget);
  });

  testWidgets(
    'Submitting a message without a loaded model warns user honestly without fake replies',
    (WidgetTester tester) async {
      await tester.pumpWidget(const SovereignApp());
      await tester.pumpAndSettle();

      // Type a prompt into the input bar
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.enterText(textField, 'Hello Sovereign AI');
      await tester.pumpAndSettle();

      // Tap send button
      final sendButton = find.byTooltip('Send message');
      expect(sendButton, findsOneWidget);
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      // Verify user message is present
      expect(
        find.byWidgetPredicate(
          (w) => w is SelectableText && w.data == 'Hello Sovereign AI',
        ),
        findsOneWidget,
      );

      // Verify that NO fake AI response was generated and honest system notice was shown
      expect(
        find.textContaining(
          'Inference Engine Offline: No local GGUF model is loaded',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'ChatGPT-style sidebar navigation drawer opens, displays brand, New Chat, and destinations',
    (WidgetTester tester) async {
      await tester.pumpWidget(const SovereignApp());
      await tester.pumpAndSettle();

      // Tap hamburger menu button
      final menuButton = find.byTooltip('Conversations & Menu');
      expect(menuButton, findsOneWidget);
      await tester.tap(menuButton);
      await tester.pumpAndSettle();

      // Drawer is open: check New Chat button, conversations header, destinations
      expect(find.text('New Chat'), findsOneWidget);
      expect(find.text('Conversations'), findsOneWidget);
      expect(find.text('Diagnostics & Audit'), findsOneWidget);

      // Tap New Chat in drawer
      await tester.tap(find.text('New Chat'));
      await tester.pumpAndSettle();

      // Drawer should close and we are on chat screen
      expect(find.text('Local & Offline Intelligence'), findsOneWidget);
    },
  );

  testWidgets(
    'Model Manager segmented tabs and Download from URL bottom sheet work cleanly',
    (WidgetTester tester) async {
      await tester.pumpWidget(const SovereignApp());
      await tester.pumpAndSettle();

      // Navigate to Models
      await tester.tap(find.text('Models'));
      await tester.pumpAndSettle();
      expect(find.text('Model Manager'), findsOneWidget);

      // Verify segmented tab buttons
      expect(find.text('Catalog'), findsOneWidget);
      expect(find.textContaining('My Models'), findsOneWidget);
      expect(find.textContaining('Downloads'), findsOneWidget);

      // Switch to My Models tab
      await tester.tap(find.textContaining('My Models'));
      await tester.pumpAndSettle();
      expect(find.text('No Models Downloaded Yet'), findsOneWidget);

      // Switch to Downloads tab
      await tester.tap(find.textContaining('Downloads'));
      await tester.pumpAndSettle();
      expect(find.text('No Active Downloads'), findsOneWidget);

      // Switch back to Catalog tab
      await tester.tap(find.text('Catalog'));
      await tester.pumpAndSettle();

      // Tap "Download from URL" quick action button
      await tester.tap(find.text('Download from URL'));
      await tester.pumpAndSettle();

      // Modal bottom sheet appears
      expect(find.text('Direct GGUF URL *'), findsOneWidget);
      expect(find.text('Start Download'), findsOneWidget);

      // Dismiss modal by tapping Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Direct GGUF URL *'), findsNothing);
    },
  );
}
