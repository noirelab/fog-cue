import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fog_cue/fog/fog.dart';
import 'package:fog_cue/screens/monitor_screen.dart';
import 'package:fog_cue/ui/theme.dart';
import 'package:fog_cue/ui/widgets.dart';

void main() {
  test('MonitorStatus.from nunca mostra Normal sem dados', () {
    MonitorStatus s({FogState? state, bool cue = false, bool stale = false}) =>
        MonitorStatus.from(state: state, cueActive: cue, sensorStale: stale);

    expect(s(), MonitorStatus.starting);
    expect(s(stale: true), MonitorStatus.noSignal);
    expect(s(state: FogState.normal), MonitorStatus.normal);
    expect(s(state: FogState.normal, stale: true), MonitorStatus.noSignal);
    expect(s(state: FogState.fogDetected, cue: true), MonitorStatus.cueActive);
    expect(s(state: FogState.recovery, cue: true), MonitorStatus.cueActive);
    expect(s(state: FogState.fogDetected, cue: true, stale: true), MonitorStatus.noSignal);
    expect(s(state: FogState.possibleFog), MonitorStatus.possibleFog);
  });

  testWidgets('StatusPanel cabe em tela estreita com fonte a 200%', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final status in MonitorStatus.values) {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Palette.light),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(2)),
          child: Scaffold(body: ListView(children: [StatusPanel(status: status, confidence: 0.5)])),
        ),
      ));
      expect(tester.takeException(), isNull, reason: '$status');
      expect(find.text(status.title), findsOneWidget);
      expect(find.byIcon(status.icon), findsOneWidget);
      // Confiança só nos estados que vêm do detector.
      final detectorState = status != MonitorStatus.starting && status != MonitorStatus.noSignal;
      expect(find.textContaining('Confiança'), detectorState ? findsOneWidget : findsNothing, reason: '$status');

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Palette.light),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(2)),
          child: Scaffold(body: ListView(children: [StatusPanel(status: status, confidence: 0.5, simple: true)])),
        ),
      ));
      expect(tester.takeException(), isNull, reason: 'simples: $status');
      expect(find.text(status.plainTitle), findsOneWidget);
      expect(find.textContaining('Confiança'), findsNothing);
    }
  });

  test('modo simples esconde a suspeita de FoG', () {
    expect(MonitorStatus.possibleFog.forParticipant(), MonitorStatus.normal);
    expect(MonitorStatus.cueActive.forParticipant(), MonitorStatus.cueActive);
  });

  testWidgets('HoldButton só dispara depois de segurado o tempo todo', (tester) async {
    var confirmed = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Palette.light),
      home: Scaffold(
        body: HoldButton(
          label: 'Segure para parar',
          holdingLabel: 'Continue segurando...',
          onConfirmed: () => confirmed++,
          onAccessibleTap: () {},
        ),
      ),
    ));

    // Soltar antes de 2 s não dispara.
    var gesture = await tester.startGesture(tester.getCenter(find.byType(HoldButton)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Continue segurando...'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(confirmed, 0);

    // Segurar 2 s dispara uma vez.
    gesture = await tester.startGesture(tester.getCenter(find.byType(HoldButton)));
    await tester.pump();
    for (var i = 0; i < 21; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(confirmed, 1);
  });
}
