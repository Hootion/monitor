import 'package:flutter/material.dart';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mutual_watch/api_client.dart';
import 'package:mutual_watch/app_state.dart';
import 'package:mutual_watch/main.dart';
import 'package:mutual_watch/models.dart';

void main() {
  test('friendlyErrorMessage hides low-level network details', () {
    expect(
      friendlyErrorMessage('SocketException: Connection refused'),
      '暂时连接不上服务器，请检查网络或 API 地址。',
    );
  });

  test('friendlyErrorMessage translates auth token errors', () {
    expect(
      friendlyErrorMessage('Missing bearer token.'),
      AppState.sessionExpiredMessage,
    );
  });

  test('protected actions expire the session when access token is missing',
      () async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(api: ApiClient(baseUrl: 'http://example.invalid'));
    state.user = const PublicUser(
      id: 'user-1',
      displayName: '测试用户',
      sharingPaused: false,
    );

    await state.createInvite();

    expect(state.user, isNull);
    expect(state.error, AppState.sessionExpiredMessage);
    expect(state.inviteCode, isNull);
  });

  test('AppUpdateInfo parses update payloads', () {
    final update = AppUpdateInfo.fromJson({
      'versionName': '0.2.0',
      'versionCode': 2,
      'apkUrl': 'https://example.com/mutual-watch.apk',
      'releaseNotes': '更新后端地址。',
      'required': true,
    });

    expect(update.versionName, '0.2.0');
    expect(update.versionCode, 2);
    expect(update.hasDownload, isTrue);
    expect(update.required, isTrue);
  });

  test('update checks do not require a logged-in session', () async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(
      updateUrl: 'https://updates.example/check',
      client: MockClient((request) async {
        expect(request.url.queryParameters['platform'], 'android');
        expect(
          request.url.queryParameters['currentVersionCode'],
          AppState.currentVersionCode.toString(),
        );
        expect(request.headers.containsKey('authorization'), isFalse);
        return http.Response(
          jsonEncode({
            'updateAvailable': true,
            'versionCode': 2008,
            'versionName': '0.2.5',
            'apkUrl': 'https://example.com/mutual-watch.apk',
            'releaseNotes': 'Update prompt fix.',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final state = AppState(api: api)..loading = false;

    expect(api.hasAccessToken, isFalse);

    final update = await state.checkForUpdate();

    expect(update?.versionCode, 2008);
    expect(state.updatePromptShown, isTrue);
  });

  test('formatInviteCode groups six digit codes', () {
    expect(formatInviteCode('123456'), '123 456');
    expect(formatInviteCode('123-456'), '123 456');
    expect(formatInviteCode('1234'), '1234');
    expect(normalizeInviteCode('12 34-56'), '123456');
  });

  test('normalizePhoneNumber preserves digits and country prefix', () {
    expect(normalizePhoneNumber('138 0013-8000'), '13800138000');
    expect(normalizePhoneNumber('+86 138-0013-8000'), '+8613800138000');
  });

  test('status labels are user friendly', () {
    expect(networkLabel('wifi'), 'Wi-Fi');
    expect(networkLabel('cellular'), '蜂窝网络');
    expect(networkNameLabel('unauthorized'), '未授权');
    expect(
      networkDisplayName(const DeviceSnapshot(
        platform: 'android',
        capturedAt: '2026-06-25T08:00:00.000Z',
        networkType: 'wifi',
        networkName: 'Home WiFi',
      )),
      'Home WiFi',
    );
    expect(
      networkDetailLabel(const DeviceSnapshot(
        platform: 'android',
        capturedAt: '2026-06-25T08:00:00.000Z',
        networkType: 'wifi',
        networkName: 'unauthorized',
      )),
      'Wi-Fi · 需要位置/Wi-Fi 权限读取名称',
    );
    expect(
      locationStatusLabel(const DeviceLocation(
        platform: 'android',
        capturedAt: '2026-06-25T08:00:00.000Z',
        status: 'unauthorized',
      )),
      '未授权',
    );
    expect(
      locationDetailLabel(const DeviceLocation(
        platform: 'android',
        capturedAt: '2026-06-25T08:00:00.000Z',
        status: 'available',
        latitude: 31.230416,
        longitude: 121.473701,
        accuracyMeters: 18,
      )),
      contains('31.230416, 121.473701'),
    );
    expect(bluetoothLabel('unauthorized'), '未授权');
    expect(bluetoothLabel('off'), '已关闭');
  });

  test('summarizeAppUsage aggregates sessions by app', () {
    final summaries = summarizeAppUsage(const [
      AppUsageSession(
        packageName: 'com.chat',
        appName: 'Chat',
        startedAt: '2026-06-25T08:00:00.000Z',
        endedAt: '2026-06-25T08:10:00.000Z',
        durationMs: 600000,
        openCount: 2,
        platform: 'android',
      ),
      AppUsageSession(
        packageName: 'com.video',
        appName: 'Video',
        startedAt: '2026-06-25T09:00:00.000Z',
        endedAt: '2026-06-25T09:05:00.000Z',
        durationMs: 300000,
        platform: 'android',
      ),
      AppUsageSession(
        packageName: 'com.chat',
        appName: 'Chat',
        startedAt: '2026-06-25T07:30:00.000Z',
        endedAt: '2026-06-25T08:20:00.000Z',
        durationMs: 120000,
        openCount: 1,
        platform: 'android',
      ),
    ]);

    final chat =
        summaries.singleWhere((item) => item.packageName == 'com.chat');
    expect(summaries, hasLength(2));
    expect(chat.durationMs, 720000);
    expect(chat.openCount, 3);
    expect(chat.sessionCount, 2);
    expect(chat.startedAt, '2026-06-25T07:30:00.000Z');
    expect(chat.endedAt, '2026-06-25T08:20:00.000Z');
  });

  test('summarizeAppUsage hides Mutual Watch self usage', () {
    final summaries = summarizeAppUsage(const [
      AppUsageSession(
        packageName: 'com.mutualwatch.mutual_watch',
        appName: 'Mutual Watch',
        startedAt: '2026-06-25T08:00:00.000Z',
        endedAt: '2026-06-25T12:00:00.000Z',
        durationMs: 14400000,
        openCount: 1,
        platform: 'android',
      ),
      AppUsageSession(
        packageName: 'com.chat',
        appName: 'Chat',
        startedAt: '2026-06-25T08:00:00.000Z',
        endedAt: '2026-06-25T08:10:00.000Z',
        durationMs: 600000,
        openCount: 1,
        platform: 'android',
      ),
    ]);

    expect(summaries, hasLength(1));
    expect(summaries.single.packageName, 'com.chat');
  });

  test('appUsageMatchesQuery searches app names and package names', () {
    const summary = AppUsageSummary(
      packageName: 'com.example.chat',
      appName: 'Daily Chat',
      startedAt: '2026-06-25T08:00:00.000Z',
      endedAt: '2026-06-25T08:20:00.000Z',
      durationMs: 1200000,
      openCount: 4,
      sessionCount: 1,
      platform: 'android',
    );

    expect(appUsageMatchesQuery(summary, 'chat'), isTrue);
    expect(appUsageMatchesQuery(summary, 'example'), isTrue);
    expect(appUsageMatchesQuery(summary, 'video'), isFalse);
  });

  test('appUsageDisplayName prefers readable names and known package fallbacks',
      () {
    const named = AppUsageSummary(
      packageName: 'com.tencent.mm',
      appName: 'WeChat',
      startedAt: '2026-06-25T08:00:00.000Z',
      endedAt: '2026-06-25T08:20:00.000Z',
      durationMs: 1200000,
      openCount: 4,
      sessionCount: 1,
      platform: 'android',
    );
    const packageOnly = AppUsageSummary(
      packageName: 'com.tencent.mm',
      appName: 'com.tencent.mm',
      startedAt: '2026-06-25T08:00:00.000Z',
      endedAt: '2026-06-25T08:20:00.000Z',
      durationMs: 1200000,
      openCount: 4,
      sessionCount: 1,
      platform: 'android',
    );

    expect(appUsageDisplayName(named), 'WeChat');
    expect(appUsageDisplayName(packageOnly), '微信');
    expect(appUsageMatchesQuery(packageOnly, '微信'), isTrue);
  });

  test('buildUsageInsightItems summarizes usage patterns', () {
    final summaries = summarizeAppUsage(const [
      AppUsageSession(
        packageName: 'com.chat',
        appName: 'Chat',
        startedAt: '2026-06-25T08:00:00.000Z',
        endedAt: '2026-06-25T08:10:00.000Z',
        durationMs: 600000,
        openCount: 2,
        platform: 'android',
      ),
      AppUsageSession(
        packageName: 'com.video',
        appName: 'Video',
        startedAt: '2026-06-25T09:00:00.000Z',
        endedAt: '2026-06-25T09:05:00.000Z',
        durationMs: 300000,
        openCount: 1,
        platform: 'android',
      ),
      AppUsageSession(
        packageName: 'com.chat',
        appName: 'Chat',
        startedAt: '2026-06-25T07:30:00.000Z',
        endedAt: '2026-06-25T08:20:00.000Z',
        durationMs: 120000,
        openCount: 1,
        platform: 'android',
      ),
    ]);

    final insights = buildUsageInsightItems(summaries);

    expect(insights.map((item) => item.title), contains('最高占比'));
    expect(insights.first.value, 'Chat');
    expect(insights.first.subtitle, contains('71%'));
    expect(insights[1].value, 'Video');
    expect(insights[2].value, '4 分钟');
  });

  test('eventDateKey groups events by local day', () {
    expect(eventDateKey('2026-06-25T08:20:00.000Z'), startsWith('2026-'));
    expect(eventDateKey('not-a-date'), 'unknown');
  });

  test('buildEventSummaryItems summarizes event activity', () {
    const events = [
      OperationEvent(
        type: 'screen_on',
        occurredAt: '2026-06-25T09:00:00.000Z',
        platform: 'android',
      ),
      OperationEvent(
        type: 'screen_off',
        occurredAt: '2026-06-25T08:30:00.000Z',
        platform: 'android',
      ),
      OperationEvent(
        type: 'network_connected',
        occurredAt: '2026-06-25T08:00:00.000Z',
        platform: 'android',
      ),
    ];
    final filtered = events
        .where((event) => eventMatchesFilter(event.type, EventFilter.device))
        .toList();

    final items = buildEventSummaryItems(
      allEvents: events,
      filteredEvents: filtered,
      filter: EventFilter.device,
    );

    expect(items.first.value, '3 条');
    expect(items.first.subtitle, contains('设备'));
    expect(items[1].value, '打开手机');
    expect(items[2].value, '设备');
    expect(items[2].subtitle, contains('100%'));
  });

  test('eventMatchesQuery searches labels, raw types, and platform', () {
    const event = OperationEvent(
      type: 'network_connected',
      occurredAt: '2026-06-25T08:00:00.000Z',
      platform: 'android',
    );

    expect(eventMatchesQuery(event, '网络'), isTrue);
    expect(eventMatchesQuery(event, 'network'), isTrue);
    expect(eventMatchesQuery(event, 'android'), isTrue);
    expect(eventMatchesQuery(event, '通话'), isFalse);
  });

  test('app opened events expose app details', () {
    const event = OperationEvent(
      type: 'app_opened',
      occurredAt: '2026-06-25T08:00:00.000Z',
      platform: 'android',
      details: {
        'appName': '微信',
        'packageName': 'com.tencent.mm',
      },
    );

    expect(eventTitle(event), '打开了微信');
    expect(eventDetailLine(event), 'com.tencent.mm');
    expect(eventMatchesQuery(event, '微信'), isTrue);
    expect(eventMatchesQuery(event, 'tencent'), isTrue);
  });

  test('operation event details tolerate JSON strings', () {
    final event = OperationEvent.fromJson({
      'type': 'app_opened',
      'occurredAt': '2026-06-25T08:00:00.000Z',
      'platform': 'android',
      'details': '{"appName":"微信","packageName":"com.tencent.mm"}',
    });

    expect(event.details?['appName'], '微信');
    expect(eventTitle(event), '打开了微信');
  });

  test('buildDashboardInsights highlights relevant status changes', () {
    final insights = buildDashboardInsights(
      snapshot: const DeviceSnapshot(
        platform: 'android',
        capturedAt: '2026-06-25T08:00:00.000Z',
        batteryPercent: 12,
        batteryCharging: false,
      ),
      report: DailyUsageReport(
        date: '2026-06-25',
        platform: 'android',
        screenTimeMs: const Duration(hours: 5).inMilliseconds,
        pickupCount: 20,
        longestContinuousMs: const Duration(hours: 1).inMilliseconds,
      ),
      partnerSharingPaused: false,
      appUsage: const [],
      latestEvents: const [],
      now: DateTime.parse('2026-06-25T09:00:00.000Z'),
    );

    expect(insights.map((item) => item.title), contains('数据有一会儿没更新'));
    expect(insights.map((item) => item.title), contains('电量偏低'));
    expect(insights.map((item) => item.title), contains('屏幕时间较长'));
    expect(insights, hasLength(3));
  });

  test('buildDashboardInsights has a calm default state', () {
    final insights = buildDashboardInsights(
      snapshot: const DeviceSnapshot(
        platform: 'ios',
        capturedAt: '2026-06-25T08:58:00.000Z',
        batteryPercent: 80,
      ),
      report: const DailyUsageReport(
        date: '2026-06-25',
        platform: 'ios',
        screenTimeMs: 600000,
        pickupCount: 2,
        longestContinuousMs: 300000,
      ),
      partnerSharingPaused: false,
      appUsage: const [],
      latestEvents: const [],
      now: DateTime.parse('2026-06-25T09:00:00.000Z'),
    );

    expect(insights.single.title, '状态平稳');
  });

  test('buildDashboardHealthItems reports freshness and coverage', () {
    final items = buildDashboardHealthItems(
      snapshot: const DeviceSnapshot(
        platform: 'android',
        capturedAt: '2026-06-25T07:30:00.000Z',
        unsupported: ['usage_report_unavailable'],
      ),
      report: null,
      partnerSharingPaused: false,
      now: DateTime.parse('2026-06-25T09:00:00.000Z'),
    );

    expect(items.map((item) => item.value), contains('需要刷新'));
    expect(items.map((item) => item.value), contains('部分缺失'));
    expect(items.map((item) => item.value), contains('共享中'));
  });

  test('buildPrivacyStatusItems summarizes consent and freshness', () {
    final items = buildPrivacyStatusItems(
      user: const PublicUser(
        id: 'user-1',
        displayName: '测试用户',
        sharingPaused: true,
      ),
      partner: const PublicUser(
        id: 'partner-1',
        displayName: 'Partner',
        sharingPaused: true,
      ),
      platform: 'android',
      usageAccessGranted: false,
      lastSyncedAt: DateTime.parse('2026-06-25T08:00:00.000Z'),
      lastRefreshedAt: DateTime.parse('2026-06-25T08:20:00.000Z'),
      now: DateTime.parse('2026-06-25T09:10:00.000Z'),
    );

    expect(items.map((item) => item.title), contains('我的共享'));
    expect(items.map((item) => item.value), contains('已暂停'));
    expect(items.map((item) => item.subtitle), contains('对方已暂停共享'));
    expect(items.map((item) => item.value), contains('需要授权'));
    expect(items.map((item) => item.value), contains('需要刷新'));
  });

  testWidgets('Auth screen smoke test', (WidgetTester tester) async {
    final state = AppState()..loading = false;
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: AuthScreen()),
      ),
    );

    expect(find.text('Mutual Watch'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byIcon(Icons.login_rounded), findsOneWidget);
  });

  testWidgets('Auth screen fits a compact phone viewport',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState()..loading = false;
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: AuthScreen()),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('手机号'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
  });

  testWidgets('Auth validation clears after typing',
      (WidgetTester tester) async {
    final state = AppState()..loading = false;
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: AuthScreen()),
      ),
    );

    await tester.tap(find.text('进入'));
    await tester.pump();

    expect(find.text('请输入有效手机号'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '13800138000');
    await tester.pump();

    expect(find.text('请输入有效手机号'), findsNothing);
  });

  testWidgets('Auth validation error can be dismissed',
      (WidgetTester tester) async {
    final state = AppState()..loading = false;
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: AuthScreen()),
      ),
    );

    await tester.tap(find.text('进入'));
    await tester.pump();

    expect(find.text('请输入有效手机号'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭提示'));
    await tester.pump();

    expect(find.text('请输入有效手机号'), findsNothing);
  });

  testWidgets('RealtimeLocationPanel explains missing AMap key',
      (WidgetTester tester) async {
    var refreshed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RealtimeLocationPanel(
            location: const DeviceLocation(
              platform: 'android',
              capturedAt: '2026-06-25T08:00:00.000Z',
              status: 'available',
              latitude: 31.230416,
              longitude: 121.473701,
              accuracyMeters: 18,
            ),
            onRefresh: () async => refreshed = true,
          ),
        ),
      ),
    );

    expect(find.text('实时定位'), findsOneWidget);
    expect(find.text('缺少高德地图 Key'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pump();

    expect(refreshed, isTrue);
  });

  testWidgets('Home shell navigates to pairing', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState()
      ..loading = false
      ..user = const PublicUser(
        id: 'user-1',
        displayName: '测试用户',
        sharingPaused: false,
      );
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: HomeShell()),
      ),
    );

    expect(find.text('绑定怎么开始'), findsOneWidget);
    expect(find.text('生成邀请码'), findsOneWidget);
    expect(find.text('双向同意 · 范围可控 · 可随时解绑'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    expect(find.text('当前绑定'), findsOneWidget);
    expect(find.text('未绑定'), findsWidgets);
    expect(find.byTooltip('粘贴'), findsOneWidget);
  });

  testWidgets('Pairing tab shows relationship panel when already bound',
      (WidgetTester tester) async {
    const partner = PublicUser(
      id: 'partner-1',
      displayName: 'Partner',
      sharingPaused: false,
      phone: '13800138000',
    );
    final state = AppState()
      ..loading = false
      ..user = const PublicUser(
        id: 'user-1',
        displayName: '测试用户',
        sharingPaused: false,
      )
      ..partner = partner;
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: HomeShell()),
      ),
    );

    await tester.tap(find.text('我的'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('绑定关系'), findsOneWidget);
    expect(find.text('Partner'), findsWidgets);
    expect(find.text('对方在共享'), findsOneWidget);
    expect(find.text('可随时解绑'), findsOneWidget);
    expect(find.byTooltip('粘贴'), findsNothing);
  });

  testWidgets('Invite code card copies code with visible feedback',
      (WidgetTester tester) async {
    final semantics = tester.ensureSemantics();
    final clipboardWrites = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final data = Map<String, dynamic>.from(call.arguments as Map);
        clipboardWrites.add(data['text'] as String);
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InviteCodeCard(code: '123456'),
        ),
      ),
    );

    expect(find.bySemanticsLabel('邀请码 123 456'), findsOneWidget);

    await tester.tap(find.byTooltip('复制邀请码'));
    await tester.pump();

    expect(clipboardWrites, ['123456']);
    expect(find.byTooltip('已复制邀请码'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.byTooltip('复制邀请码'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('Home shell uses navigation rail on wide viewports',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState()
      ..loading = false
      ..user = const PublicUser(
        id: 'user-1',
        displayName: '测试用户',
        sharingPaused: false,
      );
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: HomeShell()),
      ),
    );

    expect(find.byType(NavigationRail), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('设置'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.drag(find.byType(ListView), const Offset(0, -760));
    await tester.pump();

    expect(find.text('数据范围'), findsOneWidget);
  });

  testWidgets('Sync action labels the in-progress state',
      (WidgetTester tester) async {
    final state = AppState()
      ..loading = false
      ..syncing = true
      ..user = const PublicUser(
        id: 'user-1',
        displayName: '测试用户',
        sharingPaused: false,
      );
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: HomeShell()),
      ),
    );

    expect(find.byTooltip('正在同步'), findsOneWidget);
    expect(find.text('正在同步'), findsOneWidget);
  });

  testWidgets('Home shell fits a narrow phone across core tabs',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const partner = PublicUser(
      id: 'partner-1',
      displayName: 'Partner',
      sharingPaused: false,
    );
    final state = AppState()
      ..loading = false
      ..usageAccessGranted = true
      ..user = const PublicUser(
        id: 'user-1',
        displayName: '测试用户',
        sharingPaused: false,
      )
      ..partner = partner
      ..overview = const PartnerOverview(
        partner: partner,
        latestSnapshot: DeviceSnapshot(
          platform: 'android',
          capturedAt: '2026-06-25T08:00:00.000Z',
          batteryPercent: 62,
          networkType: 'wifi',
        ),
        dailyReport: DailyUsageReport(
          date: '2026-06-25',
          platform: 'android',
          screenTimeMs: 1800000,
          pickupCount: 6,
          longestContinuousMs: 600000,
        ),
      )
      ..appUsage = const [
        AppUsageSession(
          packageName: 'com.chat',
          appName: 'Chat',
          startedAt: '2026-06-25T08:00:00.000Z',
          endedAt: '2026-06-25T08:20:00.000Z',
          durationMs: 1200000,
          openCount: 4,
          platform: 'android',
        ),
      ]
      ..events = const [
        OperationEvent(
          type: 'screen_on',
          occurredAt: '2026-06-25T09:00:00.000Z',
          platform: 'android',
        ),
      ];
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: HomeShell()),
      ),
    );

    for (final label in ['总览', '应用', '记录', '我的']) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Dashboard health panel fits a compact phone viewport',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const partner = PublicUser(
      id: 'partner-1',
      displayName: 'Partner',
      sharingPaused: false,
    );
    final state = AppState()
      ..loading = false
      ..user = const PublicUser(
        id: 'user-1',
        displayName: '测试用户',
        sharingPaused: false,
      )
      ..partner = partner
      ..overview = const PartnerOverview(
        partner: partner,
        latestSnapshot: DeviceSnapshot(
          platform: 'android',
          capturedAt: '2026-06-25T08:00:00.000Z',
          batteryPercent: 72,
          networkType: 'wifi',
        ),
        dailyReport: DailyUsageReport(
          date: '2026-06-25',
          platform: 'android',
          screenTimeMs: 1800000,
          pickupCount: 6,
          longestContinuousMs: 600000,
        ),
      );
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: HomeShell()),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('数据健康度'), findsOneWidget);
    expect(find.text('共享中'), findsWidgets);
  });

  testWidgets('Dashboard warns when my sharing is paused',
      (WidgetTester tester) async {
    const partner = PublicUser(
      id: 'partner-1',
      displayName: 'Partner',
      sharingPaused: false,
    );
    final state = AppState()
      ..loading = false
      ..user = const PublicUser(
        id: 'user-1',
        displayName: '测试用户',
        sharingPaused: true,
      )
      ..partner = partner
      ..overview = const PartnerOverview(partner: partner);
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: HomeShell()),
      ),
    );

    expect(find.text('你已暂停共享'), findsOneWidget);
    expect(find.text('对方暂时看不到你的新状态，可在“我的-设置”里恢复。'), findsOneWidget);
  });

  testWidgets('Dashboard prompts when usage access is missing',
      (WidgetTester tester) async {
    final state = AppState()
      ..loading = false
      ..usageAccessGranted = false
      ..user = const PublicUser(
        id: 'user-1',
        displayName: '测试用户',
        sharingPaused: false,
      );
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: HomeShell()),
      ),
    );

    expect(find.text('先开启使用情况访问'), findsOneWidget);
    expect(find.text('打开授权设置'), findsOneWidget);
  });

  testWidgets('App usage tab shows compact usage insights',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState()
      ..loading = false
      ..user = const PublicUser(
        id: 'user-1',
        displayName: '测试用户',
        sharingPaused: false,
      )
      ..appUsage = const [
        AppUsageSession(
          packageName: 'com.chat',
          appName: 'Chat',
          startedAt: '2026-06-25T08:00:00.000Z',
          endedAt: '2026-06-25T08:20:00.000Z',
          durationMs: 1200000,
          openCount: 4,
          platform: 'android',
        ),
        AppUsageSession(
          packageName: 'com.video',
          appName: 'Video',
          startedAt: '2026-06-25T09:00:00.000Z',
          endedAt: '2026-06-25T09:30:00.000Z',
          durationMs: 1800000,
          openCount: 2,
          platform: 'android',
        ),
      ];
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: HomeShell()),
      ),
    );

    await tester.tap(find.text('应用'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('使用洞察'), findsOneWidget);
    expect(find.text('最高占比'), findsOneWidget);
    expect(find.text('平均单次'), findsOneWidget);
  });

  testWidgets('App usage search filters and clears results',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState()
      ..loading = false
      ..user = const PublicUser(
        id: 'user-1',
        displayName: '测试用户',
        sharingPaused: false,
      )
      ..appUsage = const [
        AppUsageSession(
          packageName: 'com.chat',
          appName: 'Chat',
          startedAt: '2026-06-25T08:00:00.000Z',
          endedAt: '2026-06-25T08:20:00.000Z',
          durationMs: 1200000,
          openCount: 4,
          platform: 'android',
        ),
        AppUsageSession(
          packageName: 'com.video',
          appName: 'Video',
          startedAt: '2026-06-25T09:00:00.000Z',
          endedAt: '2026-06-25T09:30:00.000Z',
          durationMs: 1800000,
          openCount: 2,
          platform: 'android',
        ),
      ];
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: HomeShell()),
      ),
    );

    await tester.tap(find.text('应用'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), 'chat');
    await tester.pump();

    expect(find.text('Chat'), findsWidgets);
    expect(find.text('Video'), findsNothing);

    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pump();

    expect(find.text('Video'), findsWidgets);
  });

  testWidgets('Events tab shows compact event summary',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState()
      ..loading = false
      ..user = const PublicUser(
        id: 'user-1',
        displayName: '测试用户',
        sharingPaused: false,
      )
      ..events = const [
        OperationEvent(
          type: 'screen_on',
          occurredAt: '2026-06-25T09:00:00.000Z',
          platform: 'android',
        ),
        OperationEvent(
          type: 'screen_off',
          occurredAt: '2026-06-25T08:30:00.000Z',
          platform: 'android',
        ),
        OperationEvent(
          type: 'network_connected',
          occurredAt: '2026-06-25T08:00:00.000Z',
          platform: 'android',
        ),
      ];
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: HomeShell()),
      ),
    );

    await tester.tap(find.text('记录'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('事件摘要'), findsOneWidget);
    expect(find.text('最近动态'), findsOneWidget);
    expect(find.text('主要类别'), findsOneWidget);
  });

  testWidgets('Events search filters and clears results',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState()
      ..loading = false
      ..user = const PublicUser(
        id: 'user-1',
        displayName: '测试用户',
        sharingPaused: false,
      )
      ..events = const [
        OperationEvent(
          type: 'screen_on',
          occurredAt: '2026-06-25T09:00:00.000Z',
          platform: 'android',
        ),
        OperationEvent(
          type: 'network_connected',
          occurredAt: '2026-06-25T08:00:00.000Z',
          platform: 'android',
        ),
      ];
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: HomeShell()),
      ),
    );

    await tester.tap(find.text('记录'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), 'network');
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(EventTile),
        matching: find.text('网络连接'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(EventTile),
        matching: find.text('打开手机'),
      ),
      findsNothing,
    );

    await tester.tap(find.byTooltip('清除事件搜索'));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(EventTile),
        matching: find.text('打开手机'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Privacy tab explains data scope on Android',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const partner = PublicUser(
      id: 'partner-1',
      displayName: 'Partner',
      sharingPaused: false,
    );
    final state = AppState()
      ..loading = false
      ..usageAccessGranted = false
      ..user = const PublicUser(
        id: 'user-1',
        displayName: '测试用户',
        sharingPaused: false,
      )
      ..partner = partner
      ..overview = const PartnerOverview(
        partner: partner,
        latestSnapshot: DeviceSnapshot(
          platform: 'android',
          capturedAt: '2026-06-25T08:00:00.000Z',
        ),
      );
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: HomeShell()),
      ),
    );

    await tester.tap(find.text('我的'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('设置'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('设置'), findsWidgets);
    expect(find.text('隐私状态'), findsOneWidget);
    expect(find.text('权限与可用性'), findsOneWidget);
    expect(find.byTooltip('应用设置'), findsOneWidget);
    expect(find.text('需要授权'), findsWidgets);
    expect(find.text('蓝牙权限'), findsOneWidget);
    expect(find.text('位置与网络名'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -760));
    await tester.pump();

    expect(find.text('数据范围'), findsOneWidget);
    expect(find.text('共享状态'), findsOneWidget);
    expect(find.text('最近位置'), findsOneWidget);
    expect(find.text('绝不采集'), findsOneWidget);
    expect(find.text('权限受限'), findsOneWidget);
    expect(find.text('应用使用明细'), findsOneWidget);
  });

  testWidgets('Privacy tab uses iOS system scope wording',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const partner = PublicUser(
      id: 'partner-1',
      displayName: 'Partner',
      sharingPaused: false,
    );
    final state = AppState()
      ..loading = false
      ..usageAccessGranted = false
      ..user = const PublicUser(
        id: 'user-1',
        displayName: '测试用户',
        sharingPaused: false,
      )
      ..partner = partner
      ..overview = const PartnerOverview(
        partner: partner,
        latestSnapshot: DeviceSnapshot(
          platform: 'ios',
          capturedAt: '2026-06-25T08:00:00.000Z',
        ),
      );
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: HomeShell()),
      ),
    );

    await tester.tap(find.text('我的'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('设置'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('设置'), findsWidgets);
    expect(find.text('隐私状态'), findsOneWidget);
    expect(find.text('权限与可用性'), findsOneWidget);
    expect(find.text('iOS 系统范围'), findsOneWidget);
    expect(find.text('系统范围'), findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(0, -360));
    await tester.pump();

    expect(find.text('系统开放状态'), findsOneWidget);
    expect(find.text('权限受限'), findsNothing);
  });
}
