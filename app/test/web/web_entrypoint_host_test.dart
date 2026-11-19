// Regression for #1510: every general Web entry follows the active host.
// An unavailable remote host must never open the phone's local engine.

import 'package:dsh_app/state/quick_panel_state.dart';
import 'package:dsh_app/ui/settings/interface_page.dart';
import 'package:dsh_app/ui/settings/index/spot_anchor.dart';
import 'package:dsh_app/ui/settings/index/spots.dart';
import 'package:dsh_app/ui/shell/home_shell.dart';
import 'package:dsh_app/ui/web/dsh_web_launcher.dart';
import 'package:dsh_app/ui/web/local_web_screen.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/support/harness.dart';
import '../engine_settings/support.dart' as engine;
import '../shell/adaptive/support.dart';

const _unavailable = 'Remote Web is unavailable on this host';

void main() {
  testWidgets('quick-panel Web refuses unavailable remote instead of opening local Web', (tester) async {
    SharedPreferences.setMockInitialValues({
      QuickPanelController.itemsKey: ['web'],
    });
    useWindow(tester, const Size(390, 844));
    await tester.pumpWidget(
      testApp(
        HomeShell(chatBuilder: (_) => const SizedBox.expand()),
        overrides: [
          ...homeOverrides(session: null),
          dshWebAccessProvider.overrideWithValue(const NoDshWeb(_unavailable)),
        ],
      ),
    );
    await pumpFrames(tester, 8);
    await tester.fling(find.byType(HomeShell), const Offset(-80, 0), 1500);
    await pumpFrames(tester, 8);
    final row = find.byKey(const ValueKey('quick-panel-web'));
    expect(row, findsOneWidget);
    await tester.tap(row);
    await tester.pump();

    expect(find.text(_unavailable), findsOneWidget);
    expect(find.byType(LocalWebScreen), findsNothing);
  });

  testWidgets('Interface > Open Web refuses unavailable remote instead of opening local Web', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await engine.pumpPage(
      tester,
      const InterfacePage(),
      height: 1600,
      overrides: [
        ...engine.engineOverrides(DshClient.withCarrier(engine.FakeSettingsHost())),
        dshWebAccessProvider.overrideWithValue(const NoDshWeb(_unavailable)),
      ],
    );
    final row = find.byKey(SpotKey(Spots.openWeb.id));
    expect(row, findsOneWidget);
    await tester.tap(row);
    await tester.pump();

    expect(find.text(_unavailable), findsOneWidget);
    expect(find.byType(LocalWebScreen), findsNothing);
  });
}
