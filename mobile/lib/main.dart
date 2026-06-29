import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:math' as math;
import 'dart:io' show Platform;

import 'package:amap_flutter_base/amap_flutter_base.dart';
import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'models.dart';

void main() {
  runApp(const MutualWatchApp());
}

const _pageMaxWidth = 980.0;
const _cardRadius = 8.0;
const _wideBreakpoint = 760.0;
const _ownAndroidPackageName = 'com.mutualwatch.mutual_watch';
final _maxAppUsageSessionMs = const Duration(hours: 4).inMilliseconds;
final _maxDailyUsageMs = const Duration(hours: 24).inMilliseconds;
final Set<Factory<OneSequenceGestureRecognizer>> _mapGestureRecognizers = {
  Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
};

class MutualWatchApp extends StatefulWidget {
  const MutualWatchApp({super.key});

  @override
  State<MutualWatchApp> createState() => _MutualWatchAppState();
}

class _MutualWatchAppState extends State<MutualWatchApp>
    with WidgetsBindingObserver {
  late final AppState state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    state = AppState()..bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    state.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    if (appState == AppLifecycleState.resumed && state.user != null) {
      state.refreshUsageAccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Mutual Watch',
            theme: _buildTheme(Brightness.light),
            darkTheme: _buildTheme(Brightness.dark),
            themeMode: ThemeMode.system,
            home: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: state.loading && state.user == null
                  ? const LoadingScreen(key: ValueKey('loading'))
                  : state.user == null
                      ? const AuthScreen(key: ValueKey('auth'))
                      : const HomeShell(key: ValueKey('home')),
            ),
          );
        },
      ),
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF0F8A8A),
    brightness: brightness,
  );
  final background = isDark ? const Color(0xFF111418) : const Color(0xFFF6F7F2);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: background,
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
        borderSide: BorderSide(color: scheme.primary, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_cardRadius)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_cardRadius)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_cardRadius)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_cardRadius)),
    ),
  );
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({
    required AppState state,
    required super.child,
    super.key,
  }) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing');
    return scope!.notifier!;
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(_cardRadius),
                ),
                child: Icon(Icons.link_rounded,
                    color: colors.onPrimaryContainer, size: 34),
              ),
              const SizedBox(height: 22),
              const CircularProgressIndicator(semanticsLabel: '正在加载'),
              const SizedBox(height: 18),
              Text('正在准备你的共享空间',
                  style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

enum AuthMode { login, register }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  AuthMode mode = AuthMode.login;
  bool obscurePassword = true;
  String? localError;

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final error = localError ?? state.error;

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;
              return Center(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                      isWide ? 32 : 20, 24, isWide ? 32 : 20, 28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(flex: 5, child: _AuthIntro(mode: mode)),
                              const SizedBox(width: 28),
                              Expanded(
                                flex: 4,
                                child: _buildAuthForm(state, colors, error),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _AuthIntro(mode: mode),
                              const SizedBox(height: 24),
                              _buildAuthForm(state, colors, error),
                            ],
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAuthForm(AppState state, ColorScheme colors, String? error) {
    return SurfacePanel(
      padding: const EdgeInsets.all(18),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<AuthMode>(
              segments: const [
                ButtonSegment(
                  value: AuthMode.login,
                  label: Text('登录'),
                  icon: Icon(Icons.login_rounded),
                ),
                ButtonSegment(
                  value: AuthMode.register,
                  label: Text('注册'),
                  icon: Icon(Icons.person_add_rounded),
                ),
              ],
              selected: {mode},
              showSelectedIcon: false,
              onSelectionChanged: state.loading
                  ? null
                  : (value) {
                      setState(() {
                        mode = value.first;
                        localError = null;
                      });
                    },
            ),
            const SizedBox(height: 18),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: mode == AuthMode.register
                  ? Padding(
                      key: const ValueKey('name-field'),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: nameController,
                        onChanged: (_) => _clearLocalError(),
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        decoration: const InputDecoration(
                          labelText: '昵称',
                          prefixIcon: Icon(Icons.badge_rounded),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('no-name-field')),
            ),
            TextField(
              controller: phoneController,
              onChanged: (_) => _clearLocalError(),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]')),
              ],
              decoration: const InputDecoration(
                labelText: '手机号',
                prefixIcon: Icon(Icons.phone_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              onChanged: (_) => _clearLocalError(),
              obscureText: obscurePassword,
              textInputAction: TextInputAction.done,
              autofillHints: [
                mode == AuthMode.login
                    ? AutofillHints.password
                    : AutofillHints.newPassword,
              ],
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: '密码',
                prefixIcon: const Icon(Icons.lock_rounded),
                suffixIcon: IconButton(
                  tooltip: obscurePassword ? '显示密码' : '隐藏密码',
                  onPressed: () =>
                      setState(() => obscurePassword = !obscurePassword),
                  icon: Icon(
                    obscurePassword
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: state.loading ? null : _submit,
              icon: state.loading
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onPrimary,
                        semanticsLabel: '正在提交',
                      ),
                    )
                  : Icon(mode == AuthMode.login
                      ? Icons.arrow_forward_rounded
                      : Icons.check_rounded),
              label: Text(mode == AuthMode.login ? '进入' : '创建账号'),
            ),
            if (error != null)
              ErrorBanner(message: error, onDismiss: _clearLocalError),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final state = AppScope.of(context);
    final name = nameController.text.trim();
    final phone = normalizePhoneNumber(phoneController.text);
    final password = passwordController.text;

    setState(() => localError = null);
    if (mode == AuthMode.register && name.isEmpty) {
      setState(() => localError = '先填写一个昵称');
      return;
    }
    if (phone.length < 5) {
      setState(() => localError = '请输入有效手机号');
      return;
    }
    if (password.length < 6) {
      setState(() => localError = '密码至少 6 位');
      return;
    }

    TextInput.finishAutofillContext();
    if (mode == AuthMode.login) {
      await state.login(phone, password);
    } else {
      await state.register(name, phone, password);
    }
  }

  void _clearLocalError() {
    AppScope.of(context).clearError();
    if (localError != null) {
      setState(() => localError = null);
    }
  }
}

class _AuthIntro extends StatelessWidget {
  const _AuthIntro({required this.mode});

  final AuthMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(_cardRadius),
          ),
          child: Icon(Icons.link_rounded,
              size: 34, color: colors.onPrimaryContainer),
        ),
        const SizedBox(height: 20),
        Text(
          'Mutual Watch',
          style: theme.textTheme.displaySmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Text(
          mode == AuthMode.login ? '关心对方状态，也保留彼此边界。' : '双方明确同意后，才开始共享轻量手机状态。',
          style: theme.textTheme.titleMedium
              ?.copyWith(color: colors.onSurfaceVariant, height: 1.35),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            StatusPill(icon: Icons.verified_user_rounded, label: '双向同意'),
            StatusPill(icon: Icons.pause_circle_rounded, label: '可随时暂停'),
            StatusPill(
                icon: Icons.no_encryption_gmailerrorred_rounded,
                label: '不采集隐私内容'),
          ],
        ),
      ],
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  bool updateCheckScheduled = false;
  AppState? _state;

  static const destinations = [
    _DestinationSpec(Icons.dashboard_rounded, '总览'),
    _DestinationSpec(Icons.apps_rounded, '应用'),
    _DestinationSpec(Icons.timeline_rounded, '记录'),
    _DestinationSpec(Icons.person_rounded, '我的'),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _state = AppScope.of(context);
    _state?.setPartnerLiveRefreshEnabled(index == 0);
    if (updateCheckScheduled) {
      return;
    }
    updateCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
  }

  @override
  void dispose() {
    _state?.setPartnerLiveRefreshEnabled(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pages = [
      DashboardTab(onOpenPairing: () => _selectIndex(3)),
      const AppUsageTab(),
      const EventsTab(),
      const MyTab(),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _wideBreakpoint;
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 68,
            title: _HomeTitle(
              pageTitle: destinations[index].label,
              partnerName: state.partner?.displayName,
              lastUpdatedAt: state.lastRefreshedAt ?? state.lastSyncedAt,
              syncing: state.syncing,
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SyncActionButton(state: state),
              ),
            ],
          ),
          body: Row(
            children: [
              if (isWide)
                SafeArea(
                  top: false,
                  child: NavigationRail(
                    selectedIndex: index,
                    extended: constraints.maxWidth >= 1040,
                    minExtendedWidth: 168,
                    labelType: constraints.maxWidth >= 1040
                        ? null
                        : NavigationRailLabelType.all,
                    onDestinationSelected: _selectIndex,
                    destinations: [
                      for (final destination in destinations)
                        NavigationRailDestination(
                          icon: Icon(destination.icon),
                          selectedIcon: Icon(destination.icon),
                          label: Text(destination.label),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: Stack(
                    children: [
                      IndexedStack(index: index, children: pages),
                      if ((state.loading || state.syncing) &&
                          state.user != null)
                        const Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(
                            minHeight: 2,
                            semanticsLabel: '正在加载',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: isWide
              ? null
              : NavigationBar(
                  selectedIndex: index,
                  onDestinationSelected: _selectIndex,
                  destinations: [
                    for (final destination in destinations)
                      NavigationDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(destination.icon),
                        label: destination.label,
                      ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _checkForUpdates() async {
    if (!mounted) {
      return;
    }
    final state = AppScope.of(context);
    final update = await state.checkForUpdate();
    if (!mounted || update == null || !update.hasDownload) {
      return;
    }
    await _showUpdateDialog(state, update);
  }

  Future<void> _showUpdateDialog(
    AppState state,
    AppUpdateInfo update,
  ) async {
    final notes = update.releaseNotes.trim();
    await showDialog<void>(
      context: context,
      barrierDismissible: !update.required,
      builder: (dialogContext) => AlertDialog(
        title: Text('发现新版本 ${update.versionName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当前版本 ${AppState.currentVersionName}，可更新到 ${update.versionName}。',
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(notes),
            ],
          ],
        ),
        actions: [
          if (!update.required)
            TextButton(
              onPressed: () {
                state.dismissUpdatePrompt();
                Navigator.of(dialogContext).pop();
              },
              child: const Text('稍后'),
            ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await state.openUpdateDownload(update);
              if (!mounted) {
                return;
              }
              showAppSnackBar(context, '已打开下载链接');
            },
            icon: const Icon(Icons.download_rounded),
            label: const Text('下载更新'),
          ),
        ],
      ),
    );
  }

  void _selectIndex(int value) {
    if (value == index) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => index = value);
    _state?.setPartnerLiveRefreshEnabled(value == 0);
  }
}

class _DestinationSpec {
  const _DestinationSpec(this.icon, this.label);

  final IconData icon;
  final String label;
}

class _HomeTitle extends StatelessWidget {
  const _HomeTitle({
    required this.pageTitle,
    this.syncing = false,
    this.partnerName,
    this.lastUpdatedAt,
  });

  final String pageTitle;
  final bool syncing;
  final String? partnerName;
  final DateTime? lastUpdatedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final updatedAt = lastUpdatedAt;
    final subtitle = syncing
        ? '正在同步'
        : partnerName == null
            ? '未绑定对象'
            : updatedAt == null
                ? '等待首次同步'
                : '更新于 ${formatRelativeDate(updatedAt)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(pageTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class SyncActionButton extends StatelessWidget {
  const SyncActionButton({required this.state, super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: state.syncing ? '正在同步' : '同步本机并刷新对方状态',
      onPressed: state.syncing
          ? null
          : () async {
              final messenger = ScaffoldMessenger.of(context);
              HapticFeedback.mediumImpact();
              await state.syncTelemetry();
              await state.refreshPartner();
              if (!context.mounted || state.error != null) {
                return;
              }
              messenger.showSnackBar(
                const SnackBar(content: Text('已同步并刷新状态')),
              );
            },
      icon: state.syncing
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: '正在同步',
              ),
            )
          : const Icon(Icons.sync_rounded),
    );
  }
}

class DashboardTab extends StatelessWidget {
  const DashboardTab({required this.onOpenPairing, super.key});

  final VoidCallback onOpenPairing;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final overview = state.overview;
    final snapshot = overview?.latestSnapshot;
    final report = overview?.dailyReport;
    final latestEvents = [...?overview?.latestEvents]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final insights = buildDashboardInsights(
      snapshot: snapshot,
      report: report,
      partnerSharingPaused: overview?.partner.sharingPaused ?? false,
      appUsage: state.appUsage,
      latestEvents: latestEvents,
    );

    return AdaptiveListPage(
      onRefresh: state.refreshPartner,
      children: [
        if (state.error != null) ErrorBanner(message: state.error!),
        if (!state.usageAccessGranted &&
            runtimePlatform().toLowerCase() == 'android') ...[
          InfoCard(
            icon: Icons.lock_clock_rounded,
            title: '先开启使用情况访问',
            subtitle: '开启后才能同步应用明细、今日前台次数和打开记录；不开启时仅显示基础状态。',
            tone: InfoTone.warning,
            action: TextButton.icon(
              onPressed: state.openUsageAccessSettings,
              icon: const Icon(Icons.settings_rounded),
              label: const Text('打开授权设置'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (state.partner == null) ...[
          EmptyPanel(
            icon: Icons.link_off_rounded,
            title: '还没有绑定对象',
            subtitle: '创建或输入邀请码后，这里会出现对方的今日状态。',
            action: FilledButton.icon(
              onPressed: onOpenPairing,
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text('去绑定'),
            ),
          ),
          const SizedBox(height: 12),
          const BindingGuidePanel(),
        ] else ...[
          if (state.user?.sharingPaused == true) ...[
            const InfoCard(
              icon: Icons.pause_circle_rounded,
              title: '你已暂停共享',
              subtitle: '对方暂时看不到你的新状态，可在“我的-设置”里恢复。',
              tone: InfoTone.warning,
            ),
            const SizedBox(height: 12),
          ],
          OverviewHeroCard(
            partner: state.partner!,
            snapshot: snapshot,
            report: report,
            sharingPaused: overview?.partner.sharingPaused ?? false,
          ),
          const SizedBox(height: 12),
          DashboardHealthPanel(
            items: buildDashboardHealthItems(
              snapshot: snapshot,
              report: report,
              partnerSharingPaused: overview?.partner.sharingPaused ?? false,
            ),
          ),
          if (insights.isNotEmpty) ...[
            const SizedBox(height: 12),
            InsightPanel(insights: insights),
          ],
          const SizedBox(height: 12),
          DashboardOverviewPanel(report: report),
          const SizedBox(height: 12),
          RealtimeLocationPanel(
            location: overview?.latestLocation,
            onRefresh: state.refreshPartner,
          ),
          const SizedBox(height: 12),
          DeviceStatusPanel(
            snapshot: snapshot,
            location: overview?.latestLocation,
          ),
          if (unsupportedItems(snapshot, report).isNotEmpty) ...[
            const SizedBox(height: 12),
            CapabilityNotice(items: unsupportedItems(snapshot, report)),
          ],
          const SizedBox(height: 18),
          SectionHeader(
            title: '最近操作',
            subtitle:
                latestEvents.isEmpty ? '暂无动态' : '最新 ${latestEvents.length} 条',
          ),
          const SizedBox(height: 10),
          if (latestEvents.isEmpty)
            const EmptyPanel(
                icon: Icons.inbox_rounded,
                title: '暂无记录',
                subtitle: '下一次同步后会自动更新。')
          else
            ...latestEvents.take(6).map((event) => EventTile(event: event)),
        ],
      ],
    );
  }
}

class BindingGuidePanel extends StatelessWidget {
  const BindingGuidePanel({super.key});

  static const steps = [
    _BindingGuideStep(
      icon: Icons.qr_code_2_rounded,
      title: '生成邀请码',
      subtitle: '一方生成 6 位邀请码，复制后发给对方。',
    ),
    _BindingGuideStep(
      icon: Icons.password_rounded,
      title: '对方输入',
      subtitle: '另一方输入邀请码，绑定关系立即建立。',
    ),
    _BindingGuideStep(
      icon: Icons.pause_circle_rounded,
      title: '随时暂停',
      subtitle: '任意一方都可以暂停共享或解除绑定。',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SurfacePanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: '绑定怎么开始',
            subtitle: '只在双方同意后共享手机状态',
            dense: true,
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < steps.length; index++) ...[
            _BindingGuideRow(index: index + 1, step: steps[index]),
            if (index != steps.length - 1)
              Divider(height: 18, color: colors.outlineVariant),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.verified_user_rounded,
                  size: 18, color: colors.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '双向同意 · 范围可控 · 可随时解绑',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BindingGuideRow extends StatelessWidget {
  const _BindingGuideRow({
    required this.index,
    required this.step,
  });

  final int index;
  final _BindingGuideStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(_cardRadius),
              ),
              child:
                  Icon(step.icon, color: colors.onPrimaryContainer, size: 20),
            ),
            Positioned(
              right: 3,
              bottom: 3,
              child: Container(
                width: 15,
                height: 15,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '$index',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onPrimary,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                step.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BindingGuideStep {
  const _BindingGuideStep({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

class OverviewHeroCard extends StatelessWidget {
  const OverviewHeroCard({
    required this.partner,
    required this.sharingPaused,
    this.snapshot,
    this.report,
    super.key,
  });

  final PublicUser partner;
  final bool sharingPaused;
  final DeviceSnapshot? snapshot;
  final DailyUsageReport? report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final battery = snapshot?.batteryPercent;
    final isCharging = snapshot?.batteryCharging == true;
    final platform = snapshot?.platform ?? report?.platform ?? 'unknown';

    return SurfacePanel(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final summary = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: colors.tertiaryContainer,
                    foregroundColor: colors.onTertiaryContainer,
                    child: Text(appInitial(partner.displayName)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          partner.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          snapshot?.model ??
                              (sharingPaused ? '对方已暂停共享' : '等待设备同步'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill(
                    icon: sharingPaused
                        ? Icons.pause_circle_rounded
                        : Icons.check_circle_rounded,
                    label: sharingPaused ? '已暂停' : '共享中',
                    emphasize: !sharingPaused,
                  ),
                  StatusPill(
                      icon: platformIcon(platform),
                      label: platformLabel(platform)),
                  if (snapshot?.capturedAt != null)
                    StatusPill(
                        icon: Icons.schedule_rounded,
                        label: formatRelativeTime(snapshot!.capturedAt)),
                ],
              ),
            ],
          );
          final batteryPanel = BatteryPanel(
            percent: battery,
            charging: isCharging,
            network: snapshot?.networkType,
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summary,
                const SizedBox(height: 18),
                batteryPanel,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: summary),
              const SizedBox(width: 18),
              SizedBox(width: 220, child: batteryPanel),
            ],
          );
        },
      ),
    );
  }
}

class DashboardHealthPanel extends StatelessWidget {
  const DashboardHealthPanel({required this.items, super.key});

  final List<DashboardHealthItem> items;

  @override
  Widget build(BuildContext context) {
    return SummaryMetricsPanel(
      title: '数据健康度',
      subtitle: '同步新鲜度与可用范围',
      items: items,
    );
  }
}

class SummaryMetricsPanel extends StatelessWidget {
  const SummaryMetricsPanel({
    required this.title,
    required this.subtitle,
    required this.items,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<SummaryMetricItem> items;

  @override
  Widget build(BuildContext context) {
    return SurfacePanel(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 680;
          final cells = [
            for (final item in items) SummaryMetricCell(item: item),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: title, subtitle: subtitle, dense: true),
              const SizedBox(height: 12),
              if (isWide)
                Row(
                  children: [
                    for (var index = 0; index < cells.length; index++) ...[
                      Expanded(child: cells[index]),
                      if (index != cells.length - 1) const SizedBox(width: 12),
                    ],
                  ],
                )
              else
                Column(
                  children: [
                    for (var index = 0; index < cells.length; index++) ...[
                      cells[index],
                      if (index != cells.length - 1)
                        Divider(
                          height: 18,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                    ],
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class SummaryMetricCell extends StatelessWidget {
  const SummaryMetricCell({required this.item, super.key});

  final SummaryMetricItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = switch (item.tone) {
      InfoTone.success => colors.primary,
      InfoTone.warning => colors.error,
      InfoTone.neutral => colors.secondary,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(_cardRadius),
          ),
          child: Icon(item.icon, color: accent, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                item.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                item.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class InsightPanel extends StatelessWidget {
  const InsightPanel({required this.insights, super.key});

  final List<DashboardInsight> insights;

  @override
  Widget build(BuildContext context) {
    return SurfacePanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: '当前摘要',
            subtitle: '根据最近同步的数据自动整理',
            dense: true,
          ),
          const SizedBox(height: 10),
          for (final insight in insights) ...[
            InsightRow(insight: insight),
            if (insight != insights.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class InsightRow extends StatelessWidget {
  const InsightRow({required this.insight, super.key});

  final DashboardInsight insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = switch (insight.tone) {
      InfoTone.success => colors.primary,
      InfoTone.warning => colors.error,
      InfoTone.neutral => colors.secondary,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(_cardRadius),
          ),
          child: Icon(insight.icon, size: 19, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                insight.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                insight.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class BatteryPanel extends StatelessWidget {
  const BatteryPanel({
    required this.percent,
    required this.charging,
    this.network,
    super.key,
  });

  final int? percent;
  final bool charging;
  final String? network;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final value = percent == null ? null : (percent!.clamp(0, 100) / 100);
    final batteryColor = value == null
        ? colors.outline
        : value < 0.2
            ? colors.error
            : colors.primary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: value,
                  strokeWidth: 7,
                  backgroundColor: colors.outlineVariant,
                  color: batteryColor,
                  semanticsLabel: '电量',
                  semanticsValue: percent == null ? '未知' : '$percent%',
                ),
                Icon(
                    charging
                        ? Icons.battery_charging_full_rounded
                        : Icons.battery_5_bar_rounded,
                    color: batteryColor),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  percent == null ? '电量未知' : '$percent%',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  charging
                      ? '正在充电'
                      : (network == null || network!.isEmpty
                          ? '等待网络状态'
                          : networkLabel(network)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardOverviewPanel extends StatelessWidget {
  const DashboardOverviewPanel({this.report, super.key});

  final DailyUsageReport? report;

  @override
  Widget build(BuildContext context) {
    final screenTime = safeDailyUsageDurationMs(report?.screenTimeMs ?? 0);
    final longestContinuous = math.min(
        screenTime, safeAppUsageDurationMs(report?.longestContinuousMs ?? 0));
    final subtitle = report == null
        ? '等待下一次同步'
        : '来自 ${platformLabel(report!.platform)} · 今日应用进入前台会话';
    final items = [
      _DashboardMetric(
        icon: Icons.smartphone_rounded,
        label: '屏幕时间',
        value: formatDuration(screenTime),
        helper: '今日累计',
      ),
      _DashboardMetric(
        icon: Icons.touch_app_rounded,
        label: '今日前台次数',
        value: '${report?.pickupCount ?? 0}',
        helper: '应用进入前台会话数',
      ),
      _DashboardMetric(
        icon: Icons.wb_twilight_rounded,
        label: '首次使用',
        value: formatTime(report?.firstUseAt),
        helper: '今日第一段记录',
      ),
      _DashboardMetric(
        icon: Icons.timer_rounded,
        label: '最长连续',
        value: formatDuration(longestContinuous),
        helper: '单次最长前台时长',
      ),
    ];

    return SurfacePanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: '今日概览', subtitle: subtitle, dense: true),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 680;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var index = 0; index < items.length; index++) ...[
                      Expanded(
                          child: _DashboardMetricCell(metric: items[index])),
                      if (index != items.length - 1)
                        SizedBox(
                          height: 76,
                          child: VerticalDivider(
                            width: 18,
                            thickness: 1,
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                    ],
                  ],
                );
              }
              final cellWidth = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 14,
                children: [
                  for (final item in items)
                    SizedBox(
                      width: cellWidth
                          .clamp(128.0, constraints.maxWidth)
                          .toDouble(),
                      child: _DashboardMetricCell(metric: item),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DashboardMetricCell extends StatelessWidget {
  const _DashboardMetricCell({required this.metric});

  final _DashboardMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(_cardRadius),
          ),
          child: Icon(metric.icon, size: 19, color: colors.onPrimaryContainer),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                metric.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                metric.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 2),
              Text(
                metric.helper,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class RealtimeLocationPanel extends StatefulWidget {
  const RealtimeLocationPanel({
    required this.location,
    required this.onRefresh,
    super.key,
  });

  final DeviceLocation? location;
  final Future<void> Function() onRefresh;

  @override
  State<RealtimeLocationPanel> createState() => _RealtimeLocationPanelState();
}

class _RealtimeLocationPanelState extends State<RealtimeLocationPanel> {
  AMapController? _controller;
  String? _approvalNumber;

  bool get _hasAmapKey => AppState.amapAndroidKey.trim().isNotEmpty;
  bool get _canRenderAmap => canRenderAmap();

  @override
  void didUpdateWidget(covariant RealtimeLocationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPoint = locationPoint(oldWidget.location);
    final newPoint = locationPoint(widget.location);
    if (oldPoint != newPoint && newPoint != null) {
      unawaited(_moveToLocation(animated: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.location;
    final point = locationPoint(location);
    final canShowMap = point != null &&
        location?.status.trim().toLowerCase() == 'available' &&
        _hasAmapKey &&
        _canRenderAmap;
    final subtitle = location == null
        ? '等待下一次同步'
        : '${locationStatusLabel(location)} · ${formatRelativeTime(location.capturedAt)}';

    return SurfacePanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: '实时定位',
            subtitle: subtitle,
            dense: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filledTonal(
                  tooltip: '刷新定位',
                  onPressed: () async => widget.onRefresh(),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                if (canShowMap) ...[
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    tooltip: '回到定位点',
                    onPressed: () async => _moveToLocation(animated: true),
                    icon: const Icon(Icons.my_location_rounded),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (canShowMap)
            _AmapLocationPreview(
              point: point,
              location: location!,
              approvalNumber: _approvalNumber,
              onMapCreated: _onMapCreated,
            )
          else
            _LocationUnavailablePreview(
              icon: locationNeedsAttention(location)
                  ? Icons.location_disabled_rounded
                  : Icons.map_rounded,
              title: _locationPreviewTitle(location),
              subtitle: _locationPreviewSubtitle(location),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                icon: Icons.location_on_rounded,
                label: locationStatusLabel(location),
                emphasize: location?.status.trim().toLowerCase() == 'available',
              ),
              StatusPill(
                icon: Icons.schedule_rounded,
                label: location == null
                    ? '等待更新'
                    : formatRelativeTime(location.capturedAt),
              ),
              if (location?.accuracyMeters != null)
                StatusPill(
                  icon: Icons.radar_rounded,
                  label: '约 ${location!.accuracyMeters!.round()} 米',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onMapCreated(AMapController controller) async {
    _controller = controller;
    await _moveToLocation(animated: false);
    final approval = await controller.getMapContentApprovalNumber();
    if (mounted && approval != null && approval.trim().isNotEmpty) {
      setState(() => _approvalNumber = approval);
    }
  }

  Future<void> _moveToLocation({required bool animated}) async {
    final controller = _controller;
    final point = locationPoint(widget.location);
    if (controller == null || point == null) {
      return;
    }
    await controller.moveCamera(
      CameraUpdate.newLatLngZoom(point, 17.5),
      animated: animated,
      duration: animated ? 260 : 0,
    );
  }
}

class _AmapLocationPreview extends StatelessWidget {
  const _AmapLocationPreview({
    required this.point,
    required this.location,
    required this.onMapCreated,
    this.approvalNumber,
  });

  final LatLng point;
  final DeviceLocation location;
  final String? approvalNumber;
  final MapCreatedCallback onMapCreated;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final marker = Marker(
      position: point,
      infoWindow: InfoWindow(
        title: '最新位置',
        snippet: locationDetailLabel(location),
      ),
    );
    final polygons = accuracyPolygons(location, colors.primary);

    return ClipRRect(
      borderRadius: BorderRadius.circular(_cardRadius),
      child: SizedBox(
        height: 260,
        child: Stack(
          children: [
            AMapWidget(
              apiKey: const AMapApiKey(
                androidKey: AppState.amapAndroidKey,
                iosKey: '',
              ),
              privacyStatement: const AMapPrivacyStatement(
                hasContains: true,
                hasShow: true,
                hasAgree: true,
              ),
              initialCameraPosition: CameraPosition(target: point, zoom: 17.5),
              gestureRecognizers: _mapGestureRecognizers,
              markers: {marker},
              polygons: polygons,
              minMaxZoomPreference: const MinMaxZoomPreference(3, 20),
              scaleEnabled: true,
              compassEnabled: true,
              zoomGesturesEnabled: true,
              scrollGesturesEnabled: true,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              buildingsEnabled: true,
              onMapCreated: onMapCreated,
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(_cardRadius),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Text(
                    approvalNumber == null || approvalNumber!.trim().isEmpty
                        ? locationDetailLabel(location)
                        : '${locationDetailLabel(location)} · $approvalNumber',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.25,
                        ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationUnavailablePreview extends StatelessWidget {
  const _LocationUnavailablePreview({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 156),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: colors.outlineVariant),
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(_cardRadius),
            ),
            child: Icon(icon, color: colors.onPrimaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DeviceStatusPanel extends StatelessWidget {
  const DeviceStatusPanel({this.snapshot, this.location, super.key});

  final DeviceSnapshot? snapshot;
  final DeviceLocation? location;

  @override
  Widget build(BuildContext context) {
    final storageProgress = snapshot?.storageUsedBytes == null ||
            snapshot?.storageTotalBytes == null ||
            snapshot!.storageTotalBytes == 0
        ? null
        : snapshot!.storageUsedBytes! / snapshot!.storageTotalBytes!;
    final battery = snapshot?.batteryPercent;
    final items = [
      _StatusLineData(
        icon: Icons.battery_5_bar_rounded,
        label: '电量',
        value: battery == null ? '-' : '$battery%',
        helper: snapshot?.batteryCharging == true ? '充电中' : '未充电',
        progress: battery == null ? null : battery / 100,
        warning: battery != null && battery < 20,
      ),
      _StatusLineData(
        icon: Icons.wifi_rounded,
        label: '网络',
        value: networkDisplayName(snapshot),
        helper: networkDetailLabel(snapshot),
      ),
      _StatusLineData(
        icon: Icons.location_on_rounded,
        label: '定位',
        value: locationStatusLabel(location),
        helper: locationDetailLabel(location),
        warning: locationNeedsAttention(location),
      ),
      _StatusLineData(
        icon: Icons.bluetooth_rounded,
        label: '蓝牙',
        value: bluetoothLabel(snapshot?.bluetoothState),
        helper: bluetoothHelper(snapshot?.bluetoothState),
        warning: snapshot?.bluetoothState == 'unauthorized',
      ),
      _StatusLineData(
        icon: Icons.storage_rounded,
        label: '存储',
        value: formatStorage(snapshot),
        helper: snapshot?.osVersion,
        progress: storageProgress,
      ),
      _StatusLineData(
        icon: Icons.volume_up_rounded,
        label: '音量',
        value: snapshot?.volumePercent == null
            ? '-'
            : '${snapshot!.volumePercent}%',
        helper: '系统媒体音量',
      ),
      _StatusLineData(
        icon: Icons.router_rounded,
        label: 'Wi-Fi 流量',
        value: formatBytes(snapshot?.wifiBytesToday),
        helper: '今日累计',
      ),
      _StatusLineData(
        icon: Icons.signal_cellular_alt_rounded,
        label: '数据流量',
        value: formatBytes(snapshot?.mobileBytesToday),
        helper: '今日累计',
      ),
      _StatusLineData(
        icon: platformIcon(snapshot?.platform ?? 'android'),
        label: '设备',
        value: snapshot?.model ?? '-',
        helper: platformLabel(snapshot?.platform ?? runtimePlatform()),
      ),
    ];

    return SurfacePanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: '手机状态',
            subtitle: snapshot == null
                ? '暂无设备快照'
                : '更新于 ${formatRelativeTime(snapshot!.capturedAt)}',
            dense: true,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;
              if (!isWide) {
                return Column(
                  children: [
                    for (var index = 0; index < items.length; index++) ...[
                      _StatusLineItem(item: items[index]),
                      if (index != items.length - 1)
                        Divider(
                          height: 18,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                    ],
                  ],
                );
              }
              final left = items.take(4).toList();
              final right = items.skip(4).toList();
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _StatusLineColumn(items: left)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: SizedBox(
                      height: 210,
                      child: VerticalDivider(
                        width: 1,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  Expanded(child: _StatusLineColumn(items: right)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatusLineColumn extends StatelessWidget {
  const _StatusLineColumn({required this.items});

  final List<_StatusLineData> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          _StatusLineItem(item: items[index]),
          if (index != items.length - 1)
            Divider(
              height: 18,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
        ],
      ],
    );
  }
}

class _StatusLineItem extends StatelessWidget {
  const _StatusLineItem({required this.item});

  final _StatusLineData item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = item.warning ? colors.error : colors.primary;
    final progress = item.progress?.clamp(0.0, 1.0).toDouble();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(item.icon, size: 22, color: accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      item.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              if (item.helper != null || progress != null) ...[
                const SizedBox(height: 4),
                if (progress != null)
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(8),
                    semanticsLabel: '${item.label}进度',
                    semanticsValue: formatPercent(progress),
                  ),
                if (item.helper != null) ...[
                  if (progress != null) const SizedBox(height: 3),
                  Text(
                    item.helper!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DashboardMetric {
  const _DashboardMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.helper,
  });

  final IconData icon;
  final String label;
  final String value;
  final String helper;
}

class _StatusLineData {
  const _StatusLineData({
    required this.icon,
    required this.label,
    required this.value,
    this.helper,
    this.progress,
    this.warning = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? helper;
  final double? progress;
  final bool warning;
}

class PairingTab extends StatelessWidget {
  const PairingTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdaptiveListPage(
      children: [
        PairingSection(),
      ],
    );
  }
}

class PairingSection extends StatefulWidget {
  const PairingSection({super.key});

  @override
  State<PairingSection> createState() => _PairingSectionState();
}

class _PairingSectionState extends State<PairingSection> {
  final codeController = TextEditingController();
  String? localError;

  @override
  void dispose() {
    codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = Theme.of(context).colorScheme;
    final error = localError ?? state.error;
    final hasPartner = state.partner != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          ErrorBanner(message: error, onDismiss: () => _dismissError(state)),
          const SizedBox(height: 12),
        ],
        if (hasPartner)
          BoundRelationshipPanel(
            partner: state.partner!,
            userSharingPaused: state.user?.sharingPaused ?? false,
            action: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.error,
                side: BorderSide(color: colors.error.withValues(alpha: 0.56)),
              ),
              onPressed: state.loading
                  ? null
                  : () async {
                      final confirmed = await confirmAction(
                        context,
                        title: '解除绑定？',
                        message: '解除后双方将停止查看对方状态，之后可以重新绑定。',
                        confirmLabel: '解除绑定',
                        danger: true,
                      );
                      if (!mounted || !confirmed) return;
                      await state.unpair();
                      if (!mounted || state.error != null) {
                        return;
                      }
                      showAppSnackBar(this.context, '已解除绑定');
                    },
              icon: const Icon(Icons.link_off_rounded),
              label: const Text('解除绑定'),
            ),
          )
        else
          SurfacePanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: '当前绑定',
                  subtitle: '每个账号同一时间绑定一个对象',
                  dense: true,
                  trailing: const StatusPill(
                    icon: Icons.person_off_rounded,
                    label: '未绑定',
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(_cardRadius),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.qr_code_2_rounded, color: colors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          state.inviteCode == null
                              ? '生成邀请码，或输入对方的邀请码。'
                              : '把验证码发给对方。',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 10),
                      TextButton.icon(
                        onPressed: state.loading
                            ? null
                            : () async {
                                await state.createInvite();
                                if (!mounted || state.error != null) {
                                  return;
                                }
                                showAppSnackBar(this.context, '邀请码已生成');
                              },
                        icon: const Icon(Icons.qr_code_rounded),
                        label:
                            Text(state.inviteCode == null ? '生成邀请码' : '重新生成'),
                      ),
                    ],
                  ),
                ),
                if (state.inviteCode != null) ...[
                  const SizedBox(height: 14),
                  InviteCodeCard(code: state.inviteCode!),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: codeController,
                  onChanged: (_) {
                    state.clearError();
                    if (localError != null) {
                      setState(() => localError = null);
                    }
                  },
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: '邀请码',
                    prefixIcon: const Icon(Icons.password_rounded),
                    counterText: '',
                    suffixIcon: IconButton(
                      tooltip: '粘贴',
                      onPressed:
                          state.loading ? null : () => _pasteInviteCode(state),
                      icon: const Icon(Icons.content_paste_rounded),
                    ),
                  ),
                  onSubmitted: (_) => _acceptInvite(state),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: state.loading ? null : () => _acceptInvite(state),
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('确认绑定'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _acceptInvite(AppState state) async {
    final code = normalizeInviteCode(codeController.text);
    setState(() => localError = null);
    if (code.length != 6) {
      setState(() => localError = '请输入完整的 6 位邀请码');
      return;
    }
    await state.acceptInvite(code);
    if (!mounted || state.error != null) {
      return;
    }
    codeController.clear();
    showAppSnackBar(context, '绑定成功');
  }

  void _dismissError(AppState state) {
    state.clearError();
    if (localError != null) {
      setState(() => localError = null);
    }
  }

  Future<void> _pasteInviteCode(AppState state) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) {
      return;
    }
    final code = normalizeInviteCode(data?.text ?? '');
    if (code.isEmpty) {
      setState(() => localError = '剪贴板里没有邀请码');
      return;
    }
    final normalized = code.length > 6 ? code.substring(0, 6) : code;
    codeController.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
    state.clearError();
    setState(() => localError = null);
  }
}

class MyTab extends StatefulWidget {
  const MyTab({super.key});

  @override
  State<MyTab> createState() => _MyTabState();
}

class _MyTabState extends State<MyTab> {
  bool showingSettings = false;

  @override
  Widget build(BuildContext context) {
    if (showingSettings) {
      return SettingsContent(
        onBack: () => setState(() => showingSettings = false),
      );
    }

    final state = AppScope.of(context);
    final user = state.user!;

    return AdaptiveListPage(
      children: [
        if (state.error != null) ...[
          ErrorBanner(message: state.error!, onDismiss: state.clearError),
          const SizedBox(height: 12),
        ],
        MyProfilePanel(
          user: user,
          partner: state.overview?.partner ?? state.partner,
          lastSyncedAt: state.lastSyncedAt,
          lastRefreshedAt: state.lastRefreshedAt,
        ),
        const SizedBox(height: 12),
        MySettingsEntryPanel(
          onOpenSettings: () => setState(() => showingSettings = true),
        ),
        const SizedBox(height: 12),
        const PairingSection(),
      ],
    );
  }
}

class MyProfilePanel extends StatelessWidget {
  const MyProfilePanel({
    required this.user,
    required this.partner,
    required this.lastSyncedAt,
    required this.lastRefreshedAt,
    super.key,
  });

  final PublicUser user;
  final PublicUser? partner;
  final DateTime? lastSyncedAt;
  final DateTime? lastRefreshedAt;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final latest = latestDate(lastSyncedAt, lastRefreshedAt);
    return SurfacePanel(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: colors.primaryContainer,
            foregroundColor: colors.onPrimaryContainer,
            child: Text(appInitial(user.displayName)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  partner == null ? '未绑定对象' : '已绑定 ${partner!.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          StatusPill(
            icon: latest == null
                ? Icons.cloud_off_rounded
                : Icons.cloud_done_rounded,
            label: latest == null ? '未同步' : formatRelativeDate(latest),
            emphasize: latest != null,
          ),
        ],
      ),
    );
  }
}

class MySettingsEntryPanel extends StatelessWidget {
  const MySettingsEntryPanel({required this.onOpenSettings, super.key});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return SurfacePanel(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.settings_rounded),
        title: const Text('设置'),
        subtitle: const Text('隐私、权限、数据范围和账号操作'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onOpenSettings,
      ),
    );
  }
}

class BoundRelationshipPanel extends StatelessWidget {
  const BoundRelationshipPanel({
    required this.partner,
    required this.userSharingPaused,
    this.action,
    super.key,
  });

  final PublicUser partner;
  final bool userSharingPaused;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final partnerPaused = partner.sharingPaused;

    return SurfacePanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: '绑定关系',
            subtitle: '已经可以互相关注状态',
            dense: true,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: colors.tertiaryContainer,
                foregroundColor: colors.onTertiaryContainer,
                child: Text(appInitial(partner.displayName)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partner.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      partner.phone ?? '绑定对象',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                icon: userSharingPaused
                    ? Icons.pause_circle_rounded
                    : Icons.check_circle_rounded,
                label: userSharingPaused ? '你已暂停' : '你在共享',
                emphasize: !userSharingPaused,
              ),
              StatusPill(
                icon: partnerPaused
                    ? Icons.pause_circle_rounded
                    : Icons.favorite_rounded,
                label: partnerPaused ? '对方已暂停' : '对方在共享',
                emphasize: !partnerPaused,
              ),
              const StatusPill(
                icon: Icons.link_off_rounded,
                label: '可随时解绑',
              ),
            ],
          ),
          if (action != null) ...[
            Divider(height: 26, color: colors.outlineVariant),
            SizedBox(width: double.infinity, child: action!),
          ],
        ],
      ),
    );
  }
}

class InviteCodeCard extends StatefulWidget {
  const InviteCodeCard({required this.code, super.key});

  final String code;

  @override
  State<InviteCodeCard> createState() => _InviteCodeCardState();
}

class _InviteCodeCardState extends State<InviteCodeCard> {
  bool copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final formattedCode = formatInviteCode(widget.code);
    return Semantics(
      container: true,
      label: '邀请码 $formattedCode',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(_cardRadius),
        ),
        child: Row(
          children: [
            Expanded(
              child: SelectableText(
                formattedCode,
                style: theme.textTheme.displaySmall?.copyWith(
                  color: colors.onSecondaryContainer,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton.filled(
              tooltip: copied ? '已复制邀请码' : '复制邀请码',
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: widget.code));
                if (!mounted) return;
                setState(() => copied = true);
                messenger.showSnackBar(const SnackBar(content: Text('邀请码已复制')));
                Future<void>.delayed(const Duration(seconds: 2), () {
                  if (mounted) {
                    setState(() => copied = false);
                  }
                });
              },
              icon: Icon(copied ? Icons.check_rounded : Icons.copy_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

enum UsageSort { duration, recent }

class UsageInsightsPanel extends StatelessWidget {
  const UsageInsightsPanel({required this.items, super.key});

  final List<UsageInsightItem> items;

  @override
  Widget build(BuildContext context) {
    return SummaryMetricsPanel(
      title: '使用洞察',
      subtitle: '按今日应用明细自动整理',
      items: items,
    );
  }
}

class _UsageControlsPanel extends StatelessWidget {
  const _UsageControlsPanel({
    required this.controller,
    required this.searchQuery,
    required this.sort,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSortChanged,
  });

  final TextEditingController controller;
  final String searchQuery;
  final UsageSort sort;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<UsageSort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final sortControl = SegmentedButton<UsageSort>(
      segments: const [
        ButtonSegment(
          value: UsageSort.duration,
          label: Text('按时长'),
          icon: Icon(Icons.bar_chart_rounded),
        ),
        ButtonSegment(
          value: UsageSort.recent,
          label: Text('按时间'),
          icon: Icon(Icons.schedule_rounded),
        ),
      ],
      selected: {sort},
      showSelectedIcon: false,
      onSelectionChanged: (value) => onSortChanged(value.first),
    );

    return SurfacePanel(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final searchField = TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: '搜索应用或包名',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: searchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清除搜索',
                      onPressed: onClearSearch,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          );
          if (constraints.maxWidth >= 620) {
            return Row(
              children: [
                Expanded(child: searchField),
                const SizedBox(width: 12),
                sortControl,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: sortControl),
            ],
          );
        },
      ),
    );
  }
}

class AppUsageTab extends StatefulWidget {
  const AppUsageTab({super.key});

  @override
  State<AppUsageTab> createState() => _AppUsageTabState();
}

class _AppUsageTabState extends State<AppUsageTab> {
  UsageSort sort = UsageSort.duration;
  final TextEditingController searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final allUsage = summarizeAppUsage(state.appUsage);
    final searchQuery = searchController.text.trim();
    final usage = allUsage
        .where((item) => appUsageMatchesQuery(item, searchQuery))
        .toList();
    usage.sort((a, b) {
      if (sort == UsageSort.duration) {
        return b.durationMs.compareTo(a.durationMs);
      }
      return b.endedAt.compareTo(a.endedAt);
    });
    final totalDuration =
        usage.fold<int>(0, (sum, item) => sum + item.durationMs);
    final totalOpens = usage.fold<int>(0, (sum, item) => sum + item.openCount);
    final maxDuration = usage.fold<int>(
        1, (current, item) => math.max(current, item.durationMs));
    final platform = state.overview?.dailyReport?.platform ??
        state.overview?.latestSnapshot?.platform ??
        runtimePlatform();
    final insightItems = buildUsageInsightItems(usage);

    return AdaptiveListPage(
      onRefresh: state.refreshPartner,
      children: [
        SectionHeader(
          title: '今日应用',
          subtitle: allUsage.isEmpty
              ? '暂无明细'
              : searchQuery.isEmpty
                  ? '${usage.length} 个应用 · ${formatDuration(totalDuration)}'
                  : '${usage.length}/${allUsage.length} 个应用 · ${formatDuration(totalDuration)}',
        ),
        const SizedBox(height: 10),
        if (allUsage.isNotEmpty) ...[
          MetricsGrid(
            metrics: [
              MetricData('总时长', formatDuration(totalDuration),
                  Icons.hourglass_bottom_rounded),
              MetricData('打开次数', '$totalOpens', Icons.ads_click_rounded),
              MetricData(
                  '应用数量',
                  searchQuery.isEmpty
                      ? '${usage.length}'
                      : '${usage.length}/${allUsage.length}',
                  Icons.apps_rounded),
              MetricData('平台', platformLabel(platform), platformIcon(platform)),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final controls = _UsageControlsPanel(
                controller: searchController,
                searchQuery: searchQuery,
                sort: sort,
                onSearchChanged: (_) => setState(() {}),
                onClearSearch: () {
                  searchController.clear();
                  setState(() {});
                },
                onSortChanged: (value) => setState(() => sort = value),
              );
              if (constraints.maxWidth >= 760 && insightItems.isNotEmpty) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: controls),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 5,
                      child: UsageInsightsPanel(items: insightItems),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  controls,
                  if (insightItems.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    UsageInsightsPanel(items: insightItems),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          if (usage.isEmpty)
            EmptyPanel(
              icon: Icons.search_off_rounded,
              title: '没有匹配应用',
              subtitle: '换个名称或包名试试。',
              action: TextButton.icon(
                onPressed: () {
                  searchController.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.close_rounded),
                label: const Text('清除搜索'),
              ),
            )
          else
            ...usage.map(
              (item) => AppUsageTile(
                summary: item,
                maxDurationMs: maxDuration,
              ),
            ),
        ] else
          EmptyPanel(
            icon: Icons.apps_outage_rounded,
            title: '暂无应用记录',
            subtitle: platform.toLowerCase() == 'ios'
                ? 'iOS 会显示系统允许共享的轻量状态。'
                : 'Android 授权后会显示应用明细。',
            action: platform.toLowerCase() == 'android'
                ? TextButton.icon(
                    onPressed: state.openUsageAccessSettings,
                    icon: const Icon(Icons.settings_rounded),
                    label: const Text('打开授权设置'),
                  )
                : null,
          ),
      ],
    );
  }
}

enum EventFilter { all, device, network, power, phone }

class EventSummaryPanel extends StatelessWidget {
  const EventSummaryPanel({required this.items, super.key});

  final List<EventSummaryItem> items;

  @override
  Widget build(BuildContext context) {
    return SummaryMetricsPanel(
      title: '事件摘要',
      subtitle: '先看整体，再筛选细节',
      items: items,
    );
  }
}

class _EventControlsPanel extends StatelessWidget {
  const _EventControlsPanel({
    required this.controller,
    required this.searchQuery,
    required this.filter,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onFilterChanged,
  });

  final TextEditingController controller;
  final String searchQuery;
  final EventFilter filter;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<EventFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final filterControl = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<EventFilter>(
        segments: const [
          ButtonSegment(
            value: EventFilter.all,
            label: Text('全部'),
            icon: Icon(Icons.all_inclusive_rounded),
          ),
          ButtonSegment(
            value: EventFilter.device,
            label: Text('设备'),
            icon: Icon(Icons.smartphone_rounded),
          ),
          ButtonSegment(
            value: EventFilter.network,
            label: Text('网络'),
            icon: Icon(Icons.wifi_rounded),
          ),
          ButtonSegment(
            value: EventFilter.power,
            label: Text('电量'),
            icon: Icon(Icons.battery_charging_full_rounded),
          ),
          ButtonSegment(
            value: EventFilter.phone,
            label: Text('通话'),
            icon: Icon(Icons.call_rounded),
          ),
        ],
        selected: {filter},
        showSelectedIcon: false,
        onSelectionChanged: (value) => onFilterChanged(value.first),
      ),
    );
    final searchField = TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onChanged: onSearchChanged,
      decoration: InputDecoration(
        hintText: '搜索事件、应用或平台',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: searchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: '清除事件搜索',
                onPressed: onClearSearch,
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );

    return SurfacePanel(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 760) {
            return Row(
              children: [
                Expanded(child: searchField),
                const SizedBox(width: 12),
                filterControl,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              filterControl,
              const SizedBox(height: 12),
              searchField,
            ],
          );
        },
      ),
    );
  }
}

class EventsTab extends StatefulWidget {
  const EventsTab({super.key});

  @override
  State<EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<EventsTab> {
  EventFilter filter = EventFilter.all;
  final TextEditingController searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final allEvents = [...state.events]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final categoryEvents = allEvents
        .where((event) => eventMatchesFilter(event.type, filter))
        .toList();
    final searchQuery = searchController.text.trim();
    final events = categoryEvents
        .where((event) => eventMatchesQuery(event, searchQuery))
        .toList();
    final summaryItems = buildEventSummaryItems(
      allEvents: allEvents,
      filteredEvents: events,
      filter: filter,
    );

    return AdaptiveListPage(
      onRefresh: state.refreshPartner,
      children: [
        SectionHeader(
          title: '操作详情',
          subtitle: allEvents.isEmpty
              ? '暂无动态'
              : searchQuery.isEmpty
                  ? '${events.length}/${allEvents.length} 条记录'
                  : '${events.length}/${categoryEvents.length} 条记录',
        ),
        const SizedBox(height: 10),
        if (summaryItems.isNotEmpty) ...[
          EventSummaryPanel(items: summaryItems),
          const SizedBox(height: 12),
        ],
        if (allEvents.isNotEmpty) ...[
          _EventControlsPanel(
            controller: searchController,
            searchQuery: searchQuery,
            filter: filter,
            onSearchChanged: (_) => setState(() {}),
            onClearSearch: () {
              searchController.clear();
              setState(() {});
            },
            onFilterChanged: (value) => setState(() => filter = value),
          ),
        ],
        const SizedBox(height: 12),
        if (allEvents.isEmpty)
          const EmptyPanel(
              icon: Icons.history_rounded,
              title: '暂无操作记录',
              subtitle: '同步后会显示状态变化。')
        else if (events.isEmpty)
          EmptyPanel(
            icon: searchQuery.isEmpty
                ? Icons.filter_alt_off_rounded
                : Icons.search_off_rounded,
            title: '没有匹配记录',
            subtitle: searchQuery.isEmpty ? '换一个分类看看。' : '换个事件名称或平台试试。',
            action: searchQuery.isEmpty
                ? null
                : TextButton.icon(
                    onPressed: () {
                      searchController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('清除搜索'),
                  ),
          )
        else
          ...buildEventTimeline(events),
      ],
    );
  }
}

class PrivacyTab extends StatelessWidget {
  const PrivacyTab({super.key});

  @override
  Widget build(BuildContext context) => const SettingsContent();
}

class SettingsContent extends StatelessWidget {
  const SettingsContent({this.onBack, super.key});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final user = state.user!;
    final partner = state.overview?.partner ?? state.partner;
    final platform = state.overview?.latestSnapshot?.platform ??
        state.overview?.dailyReport?.platform ??
        runtimePlatform();

    return AdaptiveListPage(
      children: [
        if (onBack != null) ...[
          SectionHeader(
            title: '设置',
            subtitle: '隐私、权限和账号操作',
            trailing: IconButton.filledTonal(
              tooltip: '返回我的',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (state.error != null) ErrorBanner(message: state.error!),
        PrivacyAccountPanel(
          user: user,
          loading: state.loading,
          onSharingChanged: (value) async {
            await state.setSharingPaused(value);
            if (!context.mounted || state.error != null) {
              return;
            }
            showAppSnackBar(context, value ? '已暂停共享' : '已恢复共享');
          },
        ),
        const SizedBox(height: 12),
        PrivacyStatusPanel(
          user: user,
          partner: partner,
          platform: platform,
          usageAccessGranted: state.usageAccessGranted,
          lastSyncedAt: state.lastSyncedAt,
          lastRefreshedAt: state.lastRefreshedAt,
        ),
        const SizedBox(height: 12),
        PermissionGuidePanel(
          platform: platform,
          usageAccessGranted: state.usageAccessGranted,
          onOpenUsageSettings: state.openUsageAccessSettings,
          onOpenAppSettings: state.openAppSettings,
        ),
        const SizedBox(height: 12),
        DataScopePanel(
          platform: platform,
          usageAccessGranted: state.usageAccessGranted,
        ),
        const SizedBox(height: 12),
        AccountActionsPanel(
          loading: state.loading,
          onDeleteData: () async {
            final confirmed = await confirmAction(
              context,
              title: '删除我的数据？',
              message: '这会删除当前账号已经上传的数据，操作完成后不可恢复。',
              confirmLabel: '删除',
              danger: true,
            );
            if (!confirmed) {
              return;
            }
            await state.deleteMyData();
            if (!context.mounted || state.error != null) {
              return;
            }
            showAppSnackBar(context, '已删除我的已上传数据');
          },
          onLogout: () async {
            final confirmed = await confirmAction(
              context,
              title: '退出登录？',
              message: '本机将清除登录状态，之后可以重新登录。',
              confirmLabel: '退出',
            );
            if (confirmed) await state.logout();
          },
        ),
      ],
    );
  }
}

class PrivacyAccountPanel extends StatelessWidget {
  const PrivacyAccountPanel({
    required this.user,
    required this.loading,
    required this.onSharingChanged,
    super.key,
  });

  final PublicUser user;
  final bool loading;
  final Future<void> Function(bool value) onSharingChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SurfacePanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onPrimaryContainer,
                child: Text(appInitial(user.displayName)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.phone ?? '当前账号',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              StatusPill(
                icon: user.sharingPaused
                    ? Icons.pause_circle_rounded
                    : Icons.check_circle_rounded,
                label: user.sharingPaused ? '已暂停' : '共享中',
                emphasize: !user.sharingPaused,
              ),
            ],
          ),
          Divider(height: 24, color: colors.outlineVariant),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: user.sharingPaused,
            onChanged: loading ? null : onSharingChanged,
            title: const Text('暂停共享'),
            subtitle:
                Text(user.sharingPaused ? '对方暂时看不到你的状态' : '对方可以看到你允许共享的状态'),
            secondary: Icon(
              user.sharingPaused
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class AccountActionsPanel extends StatelessWidget {
  const AccountActionsPanel({
    required this.loading,
    required this.onDeleteData,
    required this.onLogout,
    super.key,
  });

  final bool loading;
  final Future<void> Function() onDeleteData;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final deleteButton = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.error,
        side: BorderSide(color: colors.error.withValues(alpha: 0.56)),
      ),
      onPressed: loading ? null : onDeleteData,
      icon: const Icon(Icons.delete_outline_rounded),
      label: const Text('删除我的数据'),
    );
    final logoutButton = TextButton.icon(
      onPressed: loading ? null : onLogout,
      icon: const Icon(Icons.logout_rounded),
      label: const Text('退出登录'),
    );

    return SurfacePanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: '账号操作',
            subtitle: '退出登录或清除已上传数据',
            dense: true,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 560) {
                return Row(
                  children: [
                    Expanded(child: deleteButton),
                    const SizedBox(width: 10),
                    Expanded(child: logoutButton),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  deleteButton,
                  const SizedBox(height: 8),
                  logoutButton,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class PrivacyStatusPanel extends StatelessWidget {
  const PrivacyStatusPanel({
    required this.user,
    required this.partner,
    required this.platform,
    required this.usageAccessGranted,
    required this.lastSyncedAt,
    required this.lastRefreshedAt,
    super.key,
  });

  final PublicUser user;
  final PublicUser? partner;
  final String platform;
  final bool usageAccessGranted;
  final DateTime? lastSyncedAt;
  final DateTime? lastRefreshedAt;

  @override
  Widget build(BuildContext context) {
    return SummaryMetricsPanel(
      title: '隐私状态',
      subtitle: '谁能看见什么，一眼确认',
      items: buildPrivacyStatusItems(
        user: user,
        partner: partner,
        platform: platform,
        usageAccessGranted: usageAccessGranted,
        lastSyncedAt: lastSyncedAt,
        lastRefreshedAt: lastRefreshedAt,
      ),
    );
  }
}

class PermissionGuidePanel extends StatelessWidget {
  const PermissionGuidePanel({
    required this.platform,
    required this.usageAccessGranted,
    required this.onOpenUsageSettings,
    required this.onOpenAppSettings,
    super.key,
  });

  final String platform;
  final bool usageAccessGranted;
  final Future<void> Function() onOpenUsageSettings;
  final Future<void> Function() onOpenAppSettings;

  @override
  Widget build(BuildContext context) {
    final isIOS = platform.toLowerCase() == 'ios';
    final usageState = isIOS
        ? 'iOS 系统范围'
        : usageAccessGranted
            ? '已开启'
            : '需要授权';
    final usageHelper = isIOS
        ? 'iOS 端会按系统开放能力展示。'
        : usageAccessGranted
            ? '可展示今日应用明细和前台次数。'
            : '开启后才会展示应用明细、前台次数和打开记录。';

    final items = [
      _PermissionGuideItem(
        icon: isIOS ? Icons.phone_iphone_rounded : Icons.query_stats_rounded,
        title: '应用使用情况',
        value: usageState,
        helper: usageHelper,
        emphasize: !isIOS && usageAccessGranted,
        warning: !isIOS && !usageAccessGranted,
        action: isIOS
            ? null
            : TextButton.icon(
                onPressed: onOpenUsageSettings,
                icon: const Icon(Icons.settings_rounded),
                label: Text(usageAccessGranted ? '管理权限' : '打开设置'),
              ),
      ),
      if (!isIOS)
        _PermissionGuideItem(
          icon: Icons.location_searching_rounded,
          title: '实时定位与后台位置',
          value: AppState.amapAndroidKey.trim().isEmpty ? '缺少高德 Key' : '系统授权控制',
          helper: '地图和后台持续更新需要位置权限；Android 11+ 通常要在应用设置里允许后台位置。',
          warning: AppState.amapAndroidKey.trim().isEmpty,
          action: TextButton.icon(
            onPressed: onOpenAppSettings,
            icon: const Icon(Icons.tune_rounded),
            label: const Text('应用设置'),
          ),
        ),
      _PermissionGuideItem(
        icon: Icons.bluetooth_rounded,
        title: '蓝牙权限',
        value: isIOS ? '系统控制' : '按系统状态显示',
        helper: isIOS
            ? 'iOS 蓝牙信息遵循系统授权和后台限制。'
            : 'Android 12+ 通常需要附近设备/蓝牙权限；拒绝后在系统设置恢复。',
      ),
      _PermissionGuideItem(
        icon: Icons.wifi_rounded,
        title: '位置与网络名',
        value: '权限控制',
        helper: '位置共享和 Wi-Fi SSID 受系统权限限制；无法读取时显示“未授权”或“系统不支持”。',
      ),
    ];

    return SurfacePanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: '权限与可用性',
            subtitle: '先说明限制，再给可操作入口',
            dense: true,
            trailing: isIOS
                ? null
                : IconButton.filledTonal(
                    tooltip: '应用设置',
                    onPressed: () async => onOpenAppSettings(),
                    icon: const Icon(Icons.tune_rounded),
                  ),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < items.length; index++) ...[
            _PermissionGuideRow(item: items[index]),
            if (index != items.length - 1)
              Divider(
                height: 20,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
          ],
        ],
      ),
    );
  }
}

class _PermissionGuideRow extends StatelessWidget {
  const _PermissionGuideRow({required this.item});

  final _PermissionGuideItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = item.warning ? colors.error : colors.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(_cardRadius),
          ),
          child: Icon(item.icon, size: 20, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(
                    icon: item.warning
                        ? Icons.warning_rounded
                        : Icons.check_circle_rounded,
                    label: item.value,
                    emphasize: item.emphasize,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                item.helper,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.32,
                ),
              ),
              if (item.action != null) ...[
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerLeft, child: item.action!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PermissionGuideItem {
  const _PermissionGuideItem({
    required this.icon,
    required this.title,
    required this.value,
    required this.helper,
    this.action,
    this.emphasize = false,
    this.warning = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final String helper;
  final Widget? action;
  final bool emphasize;
  final bool warning;
}

class DataScopePanel extends StatelessWidget {
  const DataScopePanel({
    required this.platform,
    required this.usageAccessGranted,
    super.key,
  });

  final String platform;
  final bool usageAccessGranted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final platformName = platformLabel(platform);
    final isIOS = platform.toLowerCase() == 'ios';
    final permissionIcon = isIOS
        ? Icons.phone_iphone_rounded
        : usageAccessGranted
            ? Icons.verified_rounded
            : Icons.lock_clock_rounded;
    final permissionLabel = isIOS
        ? '系统范围'
        : usageAccessGranted
            ? '权限可用'
            : '权限受限';
    final sharedItems = [
      const _DataScopeFact(
        icon: Icons.battery_charging_full_rounded,
        title: '设备状态',
        subtitle: '电量、充电、音量、网络、蓝牙与存储概况。',
      ),
      const _DataScopeFact(
        icon: Icons.query_stats_rounded,
        title: '今日摘要',
        subtitle: '屏幕时间、前台次数、首次使用与最长连续使用。',
      ),
      const _DataScopeFact(
        icon: Icons.location_on_rounded,
        title: '最近位置',
        subtitle: '仅在授权后同步最近位置、更新时间和定位精度。',
      ),
      if (isIOS)
        const _DataScopeFact(
          icon: Icons.phone_iphone_rounded,
          title: '系统开放状态',
          subtitle: '仅展示 iOS 允许后台读取的轻量状态。',
        )
      else
        const _DataScopeFact(
          icon: Icons.apps_rounded,
          title: '应用使用明细',
          subtitle: '仅在 Android 授权后展示应用、时长与打开次数。',
        ),
      const _DataScopeFact(
        icon: Icons.timeline_rounded,
        title: '最近动态',
        subtitle: '开关屏、网络变化、充电状态等设备事件。',
      ),
    ];
    const blockedItems = [
      _DataScopeFact(
        icon: Icons.sms_failed_outlined,
        title: '短信与联系人',
        subtitle: '不会读取通讯录、短信、邮件或聊天内容。',
      ),
      _DataScopeFact(
        icon: Icons.mic_off_rounded,
        title: '录音与截图',
        subtitle: '不会采集通话录音、麦克风、照片或屏幕截图。',
      ),
      _DataScopeFact(
        icon: Icons.password_rounded,
        title: '输入与账号',
        subtitle: '不会记录键盘输入、账号密码或支付信息。',
      ),
    ];
    final platformSubtitle = isIOS
        ? 'iOS 端遵循系统开放能力，不读取应用使用明细或后台私密内容。'
        : usageAccessGranted
            ? 'Android 使用情况访问权限已开启，可展示应用使用明细。'
            : 'Android 未开启使用情况访问权限，应用明细会保持为空。';

    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: colors.secondaryContainer,
                foregroundColor: colors.onSecondaryContainer,
                child: const Icon(Icons.privacy_tip_rounded, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '数据范围',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '只同步双方同意共享的手机状态。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              StatusPill(icon: platformIcon(platform), label: platformName),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                icon: permissionIcon,
                label: permissionLabel,
                emphasize: !isIOS && usageAccessGranted,
              ),
              const StatusPill(icon: Icons.handshake_rounded, label: '双向同意'),
              const StatusPill(icon: Icons.pause_circle_rounded, label: '随时暂停'),
            ],
          ),
          const SizedBox(height: 16),
          _DataScopeSection(
            title: '共享状态',
            icon: Icons.visibility_rounded,
            facts: sharedItems,
          ),
          Divider(height: 26, color: colors.outlineVariant),
          const _BlockedDataScopeSection(
            title: '绝不采集',
            icon: Icons.shield_outlined,
            facts: blockedItems,
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(_cardRadius),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(platformIcon(platform),
                    size: 20, color: colors.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    platformSubtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.35,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DataScopeSection extends StatelessWidget {
  const _DataScopeSection({
    required this.title,
    required this.icon,
    required this.facts,
  });

  final String title;
  final IconData icon;
  final List<_DataScopeFact> facts;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: colors.secondary),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 560 ? 2 : 1;
            final spacing = columns == 2 ? 10.0 : 0.0;
            final itemWidth = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - spacing) / 2;

            return Wrap(
              spacing: spacing,
              runSpacing: 10,
              children: [
                for (final fact in facts)
                  SizedBox(
                    width: itemWidth,
                    child: _DataScopeFactRow(fact: fact),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _BlockedDataScopeSection extends StatelessWidget {
  const _BlockedDataScopeSection({
    required this.title,
    required this.icon,
    required this.facts,
  });

  final String title;
  final IconData icon;
  final List<_DataScopeFact> facts;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: colors.secondary),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final fact in facts)
              StatusPill(icon: fact.icon, label: fact.title),
          ],
        ),
      ],
    );
  }
}

class _DataScopeFactRow extends StatelessWidget {
  const _DataScopeFactRow({required this.fact});

  final _DataScopeFact fact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: colors.secondaryContainer.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(_cardRadius),
          ),
          child: Icon(fact.icon, size: 19, color: colors.onSecondaryContainer),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fact.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 2),
              Text(
                fact.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.32,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DataScopeFact {
  const _DataScopeFact({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

class AdaptiveListPage extends StatelessWidget {
  const AdaptiveListPage({
    required this.children,
    this.onRefresh,
    super.key,
  });

  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal =
            constraints.maxWidth >= _wideBreakpoint ? 28.0 : 16.0;
        final list = ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(horizontal, 10, horizontal, 24),
          children: children,
        );
        final content = Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _pageMaxWidth),
            child: onRefresh == null
                ? list
                : RefreshIndicator(onRefresh: onRefresh!, child: list),
          ),
        );
        return content;
      },
    );
  }
}

class SurfacePanel extends StatelessWidget {
  const SurfacePanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      elevation: Theme.of(context).brightness == Brightness.dark ? 0 : 1,
      shadowColor: colors.shadow.withValues(alpha: 0.08),
      surfaceTintColor: colors.surfaceTint.withValues(alpha: 0.04),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.72)),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    this.dense = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: (dense
                        ? theme.textTheme.titleMedium
                        : theme.textTheme.titleLarge)
                    ?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing!,
        ],
      ],
    );
  }
}

class MetricsGrid extends StatelessWidget {
  const MetricsGrid({required this.metrics, super.key});

  final List<MetricData> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 840 ? 4 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: metrics.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: 124,
          ),
          itemBuilder: (context, index) => MetricCard(metric: metrics[index]),
        );
      },
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({required this.metric, super.key});

  final MetricData metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = metric.warning ? colors.error : colors.primary;
    final progress = metric.progress?.clamp(0.0, 1.0).toDouble();
    return SurfacePanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(metric.icon, size: 22, color: accent),
              const Spacer(),
              if (progress != null)
                SizedBox(
                  width: 38,
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(8),
                    semanticsLabel: '${metric.label}进度',
                    semanticsValue: formatPercent(progress),
                  ),
                ),
            ],
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              metric.value,
              maxLines: 1,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 4),
          Text(metric.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium),
          if (metric.helper != null)
            Text(
              metric.helper!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class MetricData {
  const MetricData(
    this.label,
    this.value,
    this.icon, {
    this.helper,
    this.progress,
    this.warning = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? helper;
  final double? progress;
  final bool warning;
}

enum InfoTone { neutral, success, warning }

class SummaryMetricItem {
  const SummaryMetricItem({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    this.tone = InfoTone.neutral,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final InfoTone tone;
}

class DashboardHealthItem extends SummaryMetricItem {
  const DashboardHealthItem({
    required super.icon,
    required super.title,
    required super.value,
    required super.subtitle,
    super.tone,
  });
}

class PrivacyStatusItem extends SummaryMetricItem {
  const PrivacyStatusItem({
    required super.icon,
    required super.title,
    required super.value,
    required super.subtitle,
    super.tone,
  });
}

class DashboardInsight {
  const DashboardInsight({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.tone = InfoTone.neutral,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final InfoTone tone;
}

List<PrivacyStatusItem> buildPrivacyStatusItems({
  required PublicUser user,
  required PublicUser? partner,
  required String platform,
  required bool usageAccessGranted,
  DateTime? lastSyncedAt,
  DateTime? lastRefreshedAt,
  DateTime? now,
}) {
  final isIOS = platform.toLowerCase() == 'ios';
  final reference = now ?? DateTime.now();
  final latestRefresh = latestDate(lastSyncedAt, lastRefreshedAt);
  final freshnessAge = latestRefresh == null
      ? null
      : reference.isBefore(latestRefresh)
          ? Duration.zero
          : reference.difference(latestRefresh);
  final freshnessTone = freshnessAge == null
      ? InfoTone.warning
      : freshnessAge.inMinutes <= 15
          ? InfoTone.success
          : freshnessAge.inMinutes <= 45
              ? InfoTone.neutral
              : InfoTone.warning;
  final freshnessValue = freshnessAge == null
      ? '未同步'
      : freshnessAge.inMinutes <= 15
          ? '刚刚更新'
          : freshnessAge.inMinutes <= 45
              ? '可参考'
              : '需要刷新';
  final freshnessSubtitle = lastSyncedAt != null && lastRefreshedAt != null
      ? '本机同步和对方刷新都有记录'
      : lastSyncedAt != null
          ? '本机状态已同步'
          : lastRefreshedAt != null
              ? '已刷新对方状态'
              : '点右上角同步获取最新状态';

  return [
    PrivacyStatusItem(
      icon: user.sharingPaused
          ? Icons.pause_circle_rounded
          : Icons.check_circle_rounded,
      title: '我的共享',
      value: user.sharingPaused ? '已暂停' : '共享中',
      subtitle: user.sharingPaused ? '对方看不到你的新状态' : '对方可看到你允许共享的状态',
      tone: user.sharingPaused ? InfoTone.warning : InfoTone.success,
    ),
    PrivacyStatusItem(
      icon: partner == null
          ? Icons.link_off_rounded
          : partner.sharingPaused
              ? Icons.pause_circle_rounded
              : Icons.favorite_rounded,
      title: '绑定状态',
      value: partner?.displayName ?? '未绑定',
      subtitle: partner == null
          ? '生成邀请码后邀请对方'
          : partner.sharingPaused
              ? '对方已暂停共享'
              : '对方正在共享',
      tone: partner == null
          ? InfoTone.neutral
          : partner.sharingPaused
              ? InfoTone.warning
              : InfoTone.success,
    ),
    PrivacyStatusItem(
      icon: isIOS
          ? Icons.phone_iphone_rounded
          : usageAccessGranted
              ? Icons.verified_rounded
              : Icons.warning_rounded,
      title: '系统权限',
      value: isIOS
          ? '系统范围'
          : usageAccessGranted
              ? '权限可用'
              : '需要授权',
      subtitle: isIOS
          ? '按 iOS 可开放能力显示'
          : usageAccessGranted
              ? '应用明细可展示'
              : '应用明细暂不完整',
      tone: isIOS
          ? InfoTone.neutral
          : usageAccessGranted
              ? InfoTone.success
              : InfoTone.warning,
    ),
    PrivacyStatusItem(
      icon: freshnessTone == InfoTone.warning
          ? Icons.update_disabled_rounded
          : Icons.cloud_done_rounded,
      title: '最近刷新',
      value: freshnessValue,
      subtitle: freshnessSubtitle,
      tone: freshnessTone,
    ),
  ];
}

List<DashboardHealthItem> buildDashboardHealthItems({
  required DeviceSnapshot? snapshot,
  required DailyUsageReport? report,
  required bool partnerSharingPaused,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final capturedAt = DateTime.tryParse(snapshot?.capturedAt ?? '')?.toLocal();
  final platform = snapshot?.platform ?? report?.platform ?? 'unknown';
  final unsupported = unsupportedItems(snapshot, report);
  final items = <DashboardHealthItem>[];

  if (capturedAt == null && report == null) {
    items.add(
      const DashboardHealthItem(
        icon: Icons.hourglass_empty_rounded,
        title: '同步状态',
        value: '等待同步',
        subtitle: '首次同步后会出现可参考的状态。',
      ),
    );
  } else if (capturedAt == null) {
    items.add(
      const DashboardHealthItem(
        icon: Icons.cloud_queue_rounded,
        title: '同步状态',
        value: '摘要可用',
        subtitle: '今日摘要已同步，设备快照待更新。',
      ),
    );
  } else {
    final age = reference.isBefore(capturedAt)
        ? Duration.zero
        : reference.difference(capturedAt);
    final tone = age.inMinutes <= 45 ? InfoTone.success : InfoTone.warning;
    final value = age.inMinutes <= 15
        ? '同步新鲜'
        : age.inMinutes <= 45
            ? '可参考'
            : age.inMinutes <= 120
                ? '需要刷新'
                : '数据偏旧';
    items.add(
      DashboardHealthItem(
        icon: tone == InfoTone.success
            ? Icons.cloud_done_rounded
            : Icons.update_disabled_rounded,
        title: '同步状态',
        value: value,
        subtitle: '${formatElapsedAge(age)}更新',
        tone: tone,
      ),
    );
  }

  if (unsupported.isEmpty) {
    items.add(
      DashboardHealthItem(
        icon: Icons.fact_check_rounded,
        title: '数据覆盖',
        value: '覆盖良好',
        subtitle:
            platform.toLowerCase() == 'ios' ? '符合 iOS 系统开放能力。' : '基础状态与今日摘要可用。',
        tone: InfoTone.success,
      ),
    );
  } else {
    final visible = unsupported.take(2).map(capabilityLabel).join('、');
    items.add(
      DashboardHealthItem(
        icon: Icons.rule_rounded,
        title: '数据覆盖',
        value: '部分缺失',
        subtitle: '$visible 暂不可用。',
        tone: InfoTone.warning,
      ),
    );
  }

  items.add(
    DashboardHealthItem(
      icon: partnerSharingPaused
          ? Icons.pause_circle_rounded
          : Icons.handshake_rounded,
      title: '共享状态',
      value: partnerSharingPaused ? '共享暂停' : '共享中',
      subtitle: partnerSharingPaused ? '对方恢复后会继续更新。' : '双方同意范围内持续同步。',
      tone: partnerSharingPaused ? InfoTone.warning : InfoTone.success,
    ),
  );

  return items;
}

List<DashboardInsight> buildDashboardInsights({
  required DeviceSnapshot? snapshot,
  required DailyUsageReport? report,
  required bool partnerSharingPaused,
  required List<AppUsageSession> appUsage,
  required List<OperationEvent> latestEvents,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final insights = <DashboardInsight>[];

  if (partnerSharingPaused) {
    insights.add(
      const DashboardInsight(
        icon: Icons.pause_circle_rounded,
        title: '对方已暂停共享',
        subtitle: '暂停期间不会继续展示新的手机状态。',
        tone: InfoTone.warning,
      ),
    );
  }

  if (snapshot == null && report == null) {
    insights.add(
      const DashboardInsight(
        icon: Icons.hourglass_empty_rounded,
        title: '等待首次同步',
        subtitle: '对方完成同步后，这里会出现今日状态摘要。',
      ),
    );
  }

  final capturedAt = DateTime.tryParse(snapshot?.capturedAt ?? '')?.toLocal();
  if (capturedAt != null && reference.difference(capturedAt).inMinutes >= 30) {
    insights.add(
      DashboardInsight(
        icon: Icons.schedule_rounded,
        title: '数据有一会儿没更新',
        subtitle: '最近快照更新于 ${formatRelativeDate(capturedAt)}。',
        tone: InfoTone.warning,
      ),
    );
  }

  final battery = snapshot?.batteryPercent;
  if (battery != null && battery <= 20 && snapshot?.batteryCharging != true) {
    insights.add(
      DashboardInsight(
        icon: Icons.battery_alert_rounded,
        title: '电量偏低',
        subtitle: '当前电量 $battery%，可以稍后留意是否开始充电。',
        tone: InfoTone.warning,
      ),
    );
  }

  final screenTime = safeDailyUsageDurationMs(report?.screenTimeMs ?? 0);
  if (screenTime >= const Duration(hours: 4).inMilliseconds) {
    insights.add(
      DashboardInsight(
        icon: Icons.smartphone_rounded,
        title: '屏幕时间较长',
        subtitle: '今日累计 ${formatDuration(screenTime)}，比普通轻量查看更高。',
        tone: InfoTone.warning,
      ),
    );
  }

  final usage = summarizeAppUsage(appUsage)
    ..sort((a, b) => b.durationMs.compareTo(a.durationMs));
  if (usage.isNotEmpty &&
      usage.first.durationMs >= const Duration(minutes: 30).inMilliseconds) {
    final top = usage.first;
    insights.add(
      DashboardInsight(
        icon: Icons.apps_rounded,
        title: '最常用：${top.appName ?? top.packageName}',
        subtitle:
            '今日累计 ${formatDuration(top.durationMs)}，打开 ${top.openCount} 次。',
      ),
    );
  }

  if (latestEvents.isNotEmpty && insights.length < 3) {
    final latest = latestEvents.first;
    insights.add(
      DashboardInsight(
        icon: eventIcon(latest.type),
        title: '最近动态：${eventTitle(latest)}',
        subtitle:
            '${formatRelativeTime(latest.occurredAt)} · ${platformLabel(latest.platform)}',
      ),
    );
  }

  if (insights.isEmpty) {
    insights.add(
      const DashboardInsight(
        icon: Icons.check_circle_rounded,
        title: '状态平稳',
        subtitle: '当前没有需要特别留意的变化。',
        tone: InfoTone.success,
      ),
    );
  }

  return insights.take(3).toList();
}

class InfoCard extends StatelessWidget {
  const InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.tone = InfoTone.neutral,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  final InfoTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final Color iconColor = switch (tone) {
      InfoTone.success => colors.primary,
      InfoTone.warning => colors.error,
      InfoTone.neutral => colors.secondary,
    };
    return SurfacePanel(
      padding: EdgeInsets.zero,
      child: ListTile(
        minVerticalPadding: 14,
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: iconColor.withValues(alpha: 0.14),
          foregroundColor: iconColor,
          child: Icon(icon, size: 21),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: action,
      ),
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SurfacePanel(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(_cardRadius),
            ),
            child: Icon(icon, size: 30, color: colors.primary),
          ),
          const SizedBox(height: 12),
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

class CapabilityNotice extends StatelessWidget {
  const CapabilityNotice({required this.items, super.key});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final visible = items.take(3).map(capabilityLabel).join('、');
    return InfoCard(
      icon: Icons.info_outline_rounded,
      title: '部分状态暂不可用',
      subtitle: visible.isEmpty ? '等待系统授权或下一次同步。' : visible,
      tone: InfoTone.warning,
    );
  }
}

class AppUsageSummary {
  const AppUsageSummary({
    required this.packageName,
    required this.startedAt,
    required this.endedAt,
    required this.durationMs,
    required this.openCount,
    required this.sessionCount,
    required this.platform,
    this.appName,
  });

  final String packageName;
  final String? appName;
  final String startedAt;
  final String endedAt;
  final int durationMs;
  final int openCount;
  final int sessionCount;
  final String platform;
}

class UsageInsightItem extends SummaryMetricItem {
  const UsageInsightItem({
    required super.icon,
    required super.title,
    required super.value,
    required super.subtitle,
    super.tone,
  });
}

class EventSummaryItem extends SummaryMetricItem {
  const EventSummaryItem({
    required super.icon,
    required super.title,
    required super.value,
    required super.subtitle,
    super.tone,
  });
}

class _MutableAppUsageSummary {
  _MutableAppUsageSummary(AppUsageSession session)
      : packageName = session.packageName,
        appName = session.appName,
        startedAt = session.startedAt,
        endedAt = session.endedAt,
        durationMs = safeAppUsageSessionDurationMs(session),
        openCount = session.openCount ?? 1,
        platform = session.platform;

  final String packageName;
  String? appName;
  String startedAt;
  String endedAt;
  int durationMs;
  int openCount;
  int sessionCount = 1;
  String platform;

  void add(AppUsageSession session) {
    appName ??= session.appName;
    startedAt = earlierIso(startedAt, session.startedAt);
    endedAt = laterIso(endedAt, session.endedAt);
    durationMs += safeAppUsageSessionDurationMs(session);
    openCount += session.openCount ?? 1;
    sessionCount += 1;
    platform = platform.isEmpty ? session.platform : platform;
  }

  AppUsageSummary toSummary() => AppUsageSummary(
        packageName: packageName,
        appName: appName,
        startedAt: startedAt,
        endedAt: endedAt,
        durationMs: durationMs,
        openCount: openCount,
        sessionCount: sessionCount,
        platform: platform,
      );
}

List<AppUsageSummary> summarizeAppUsage(List<AppUsageSession> sessions) {
  final summaries = <String, _MutableAppUsageSummary>{};
  for (final session in sessions) {
    if (!shouldShowAppUsageSession(session)) {
      continue;
    }
    summaries.update(
      session.packageName,
      (summary) => summary..add(session),
      ifAbsent: () => _MutableAppUsageSummary(session),
    );
  }
  return summaries.values.map((summary) => summary.toSummary()).toList();
}

bool shouldShowAppUsageSession(AppUsageSession session) {
  return session.packageName.trim().toLowerCase() != _ownAndroidPackageName &&
      safeAppUsageSessionDurationMs(session) > 0;
}

int safeDailyUsageDurationMs(int durationMs) {
  return math.max(0, math.min(durationMs, _maxDailyUsageMs));
}

int safeAppUsageDurationMs(int durationMs) {
  return math.max(0, math.min(durationMs, _maxAppUsageSessionMs));
}

int safeAppUsageSessionDurationMs(AppUsageSession session) {
  final rawDuration = safeAppUsageDurationMs(session.durationMs);
  final startedAt = DateTime.tryParse(session.startedAt);
  final endedAt = DateTime.tryParse(session.endedAt);
  if (startedAt == null || endedAt == null || !endedAt.isAfter(startedAt)) {
    return rawDuration;
  }
  final clockDuration =
      math.max(0, endedAt.difference(startedAt).inMilliseconds);
  return math.min(rawDuration, safeAppUsageDurationMs(clockDuration));
}

List<UsageInsightItem> buildUsageInsightItems(List<AppUsageSummary> usage) {
  if (usage.isEmpty) {
    return const [];
  }

  final totalDuration =
      usage.fold<int>(0, (sum, item) => sum + math.max(0, item.durationMs));
  final totalOpens = usage.fold<int>(0, (sum, item) => sum + item.openCount);
  final byDuration = [...usage]
    ..sort((a, b) => b.durationMs.compareTo(a.durationMs));
  final byRecent = [...usage]..sort((a, b) => b.endedAt.compareTo(a.endedAt));
  final top = byDuration.first;
  final recent = byRecent.first;
  final averageDuration = totalOpens <= 0 ? 0 : totalDuration ~/ totalOpens;
  final topShare = totalDuration <= 0 ? 0.0 : top.durationMs / totalDuration;

  return [
    UsageInsightItem(
      icon: Icons.stacked_bar_chart_rounded,
      title: '最高占比',
      value: appUsageDisplayName(top),
      subtitle:
          '${formatDuration(top.durationMs)} · ${formatPercent(topShare)}',
      tone: topShare >= 0.45 ? InfoTone.warning : InfoTone.neutral,
    ),
    UsageInsightItem(
      icon: Icons.update_rounded,
      title: '最近使用',
      value: appUsageDisplayName(recent),
      subtitle:
          '${formatTime(recent.endedAt)} 结束 · ${formatDuration(recent.durationMs)}',
    ),
    UsageInsightItem(
      icon: Icons.av_timer_rounded,
      title: '平均单次',
      value: formatDuration(averageDuration),
      subtitle: '$totalOpens 次打开 · ${usage.length} 个应用',
      tone: averageDuration >= const Duration(minutes: 20).inMilliseconds
          ? InfoTone.warning
          : InfoTone.success,
    ),
  ];
}

String appUsageDisplayName(AppUsageSummary summary) {
  final appName = summary.appName?.trim();
  if (appName != null &&
      appName.isNotEmpty &&
      appName.toLowerCase() != summary.packageName.toLowerCase()) {
    return appName;
  }
  return friendlyPackageName(summary.packageName) ?? summary.packageName;
}

String? friendlyPackageName(String packageName) {
  final normalized = packageName.trim().toLowerCase();
  const knownPackages = {
    'com.tencent.mm': '微信',
    'com.tencent.mobileqq': 'QQ',
    'com.eg.android.alipaygphone': '支付宝',
    'com.taobao.taobao': '淘宝',
    'com.jingdong.app.mall': '京东',
    'com.ss.android.ugc.aweme': '抖音',
    'com.smile.gifmaker': '快手',
    'com.kuaishou.nebula': '快手极速版',
    'com.sina.weibo': '微博',
    'com.zhihu.android': '知乎',
    'com.netease.cloudmusic': '网易云音乐',
    'com.tencent.qqmusic': 'QQ音乐',
    'com.tencent.mtt': 'QQ浏览器',
    'com.android.chrome': 'Chrome',
    'com.android.browser': '浏览器',
    'com.baidu.searchbox': '百度',
    'com.autonavi.minimap': '高德地图',
    'com.baidu.baidumap': '百度地图',
    'com.xingin.xhs': '小红书',
    'tv.danmaku.bili': '哔哩哔哩',
    'com.tencent.qqlive': '腾讯视频',
    'com.youku.phone': '优酷',
    'com.qiyi.video': '爱奇艺',
    'com.ss.android.article.news': '今日头条',
    'com.ss.android.article.lite': '今日头条极速版',
  };
  final known = knownPackages[normalized];
  if (known != null) {
    return known;
  }
  final parts = normalized.split('.').where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) {
    return null;
  }
  final tail = parts.last;
  if (tail.length <= 2 || RegExp(r'^\d+$').hasMatch(tail)) {
    return null;
  }
  return tail
      .split(RegExp(r'[_-]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}

bool appUsageMatchesQuery(AppUsageSummary summary, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return true;
  }
  return appUsageDisplayName(summary).toLowerCase().contains(normalized) ||
      summary.packageName.toLowerCase().contains(normalized);
}

class AppUsageTile extends StatelessWidget {
  const AppUsageTile({
    required this.summary,
    required this.maxDurationMs,
    super.key,
  });

  final AppUsageSummary summary;
  final int maxDurationMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final progress =
        (summary.durationMs / maxDurationMs).clamp(0.0, 1.0).toDouble();
    final displayName = appUsageDisplayName(summary);
    final showPackageName =
        displayName.toLowerCase() != summary.packageName.toLowerCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfacePanel(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: colors.primaryContainer,
              foregroundColor: colors.onPrimaryContainer,
              child: Text(appInitial(displayName)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(formatDuration(summary.durationMs),
                          style: theme.textTheme.labelLarge),
                    ],
                  ),
                  if (showPackageName) ...[
                    const SizedBox(height: 2),
                    Text(
                      summary.packageName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      semanticsLabel: '$displayName 使用占比',
                      semanticsValue: formatPercent(progress),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${formatTime(summary.startedAt)} - ${formatTime(summary.endedAt)}'
                    ' · ${summary.openCount} 次'
                    '${summary.sessionCount > 1 ? ' · ${summary.sessionCount} 段' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<Widget> buildEventTimeline(List<OperationEvent> events) {
  final children = <Widget>[];
  String? previousKey;
  for (final event in events) {
    final key = eventDateKey(event.occurredAt);
    if (key != previousKey) {
      children.add(DateDivider(label: formatEventDateHeader(event.occurredAt)));
      previousKey = key;
    }
    children.add(EventTile(event: event));
  }
  return children;
}

class DateDivider extends StatelessWidget {
  const DateDivider({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: colors.outlineVariant)),
        ],
      ),
    );
  }
}

class EventTile extends StatelessWidget {
  const EventTile({required this.event, super.key});

  final OperationEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = eventTitle(event);
    final detail = eventDetailLine(event);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfacePanel(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(_cardRadius),
              ),
              child: Icon(eventIcon(event.type), color: colors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${formatDateTime(event.occurredAt)} · ${platformLabel(event.platform)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    required this.message,
    this.onDismiss,
    super.key,
  });

  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final displayMessage = friendlyErrorMessage(message);
    final dismiss = onDismiss ?? AppScope.of(context).clearError;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(_cardRadius),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: colors.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                displayMessage,
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
            IconButton(
              tooltip: '关闭提示',
              onPressed: dismiss,
              color: colors.onErrorContainer,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.icon,
    required this.label,
    this.emphasize = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background =
        emphasize ? colors.primaryContainer : colors.surfaceContainerHighest;
    final foreground =
        emphasize ? colors.onPrimaryContainer : colors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 6),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: foreground)),
        ],
      ),
    );
  }
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool danger = false,
}) async {
  final colors = Theme.of(context).colorScheme;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showAppSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

String earlierIso(String current, String next) {
  final currentValue = DateTime.tryParse(current);
  final nextValue = DateTime.tryParse(next);
  if (currentValue == null) {
    return next;
  }
  if (nextValue == null) {
    return current;
  }
  return nextValue.isBefore(currentValue) ? next : current;
}

String laterIso(String current, String next) {
  final currentValue = DateTime.tryParse(current);
  final nextValue = DateTime.tryParse(next);
  if (currentValue == null) {
    return next;
  }
  if (nextValue == null) {
    return current;
  }
  return nextValue.isAfter(currentValue) ? next : current;
}

DateTime? latestDate(DateTime? first, DateTime? second) {
  if (first == null) return second;
  if (second == null) return first;
  return second.isAfter(first) ? second : first;
}

String formatDuration(int milliseconds) {
  if (milliseconds <= 0) return '0 分钟';
  final minutes = (milliseconds / 60000).round();
  if (minutes <= 0) return '<1 分钟';
  if (minutes < 60) return '$minutes 分钟';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分钟';
}

String friendlyErrorMessage(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('socketexception') ||
      lower.contains('connection refused') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection timed out')) {
    return '暂时连接不上服务器，请检查网络或 API 地址。';
  }
  if (lower.contains('missing bearer token') ||
      lower.contains('user no longer exists') ||
      lower.contains('refresh token is invalid')) {
    return AppState.sessionExpiredMessage;
  }
  return message
      .replaceFirst('Exception: ', '')
      .replaceFirst('ApiException: ', '')
      .trim();
}

String formatInviteCode(String code) {
  final compact = normalizeInviteCode(code);
  if (compact.length != 6) {
    return code;
  }
  return '${compact.substring(0, 3)} ${compact.substring(3)}';
}

String normalizeInviteCode(String code) {
  return code.replaceAll(RegExp(r'\D'), '');
}

String normalizePhoneNumber(String value) {
  return value.replaceAll(RegExp(r'[\s-]'), '');
}

String formatTime(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final value = DateTime.tryParse(iso)?.toLocal();
  if (value == null) return '-';
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String formatDateTime(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final value = DateTime.tryParse(iso)?.toLocal();
  if (value == null) return '-';
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$month/$day ${formatTime(iso)}';
}

String eventDateKey(String? iso) {
  final value = DateTime.tryParse(iso ?? '')?.toLocal();
  if (value == null) {
    return 'unknown';
  }
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String formatEventDateHeader(String? iso) {
  final value = DateTime.tryParse(iso ?? '')?.toLocal();
  if (value == null) {
    return '未知日期';
  }
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(value.year, value.month, value.day);
  final dayDelta = today.difference(date).inDays;
  if (dayDelta == 0) {
    return '今天';
  }
  if (dayDelta == 1) {
    return '昨天';
  }
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}/$month/$day';
}

String formatRelativeTime(String? iso) {
  if (iso == null || iso.isEmpty) return '刚刚';
  final value = DateTime.tryParse(iso)?.toLocal();
  if (value == null) return '刚刚';
  return formatRelativeDate(value);
}

String formatRelativeDate(DateTime value) {
  final diff = DateTime.now().difference(value);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  return formatDateTime(value.toIso8601String());
}

String formatElapsedAge(Duration age) {
  if (age.inMinutes < 1) return '刚刚';
  if (age.inHours < 1) return '${age.inMinutes} 分钟前';
  if (age.inDays < 1) return '${age.inHours} 小时前';
  return '${age.inDays} 天前';
}

String formatPercent(double value) {
  final normalized = value.clamp(0.0, 1.0);
  return '${(normalized * 100).round()}%';
}

String formatBytes(int? bytes) {
  if (bytes == null) {
    return '-';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}

String formatStorage(DeviceSnapshot? snapshot) {
  if (snapshot?.storageUsedBytes == null ||
      snapshot?.storageTotalBytes == null) {
    return '-';
  }
  return '${formatBytes(snapshot!.storageUsedBytes)} / ${formatBytes(snapshot.storageTotalBytes)}';
}

String? speedLabel(int? kbps) {
  if (kbps == null) return null;
  if (kbps < 1024) return '$kbps Kbps';
  return '${(kbps / 1024).toStringAsFixed(1)} Mbps';
}

IconData platformIcon(String platform) {
  return switch (platform.toLowerCase()) {
    'ios' => Icons.phone_iphone_rounded,
    'android' => Icons.phone_android_rounded,
    _ => Icons.devices_rounded,
  };
}

String platformLabel(String platform) {
  return switch (platform.toLowerCase()) {
    'ios' => 'iOS',
    'android' => 'Android',
    _ => '未知平台',
  };
}

String networkLabel(String? value) {
  final normalized = value?.trim().toLowerCase();
  return switch (normalized) {
    null || '' => '-',
    'wifi' => 'Wi-Fi',
    'cellular' => '蜂窝网络',
    'offline' => '离线',
    'ethernet' => '以太网',
    'bluetooth' => '蓝牙共享',
    'unknown' => '未知网络',
    _ => value!,
  };
}

String networkNameLabel(String? value) {
  final normalized = value?.trim();
  final lower = normalized?.toLowerCase();
  return switch (lower) {
    null || '' => '-',
    'unauthorized' => '未授权',
    'unsupported' => '系统不支持',
    'unknown' || '<unknown ssid>' => '未知网络',
    _ => normalized!,
  };
}

String networkDisplayName(DeviceSnapshot? snapshot) {
  final name = networkNameLabel(snapshot?.networkName);
  if (name != '-') {
    return name;
  }
  return networkLabel(snapshot?.networkType);
}

String networkDetailLabel(DeviceSnapshot? snapshot) {
  final speed = speedLabel(snapshot?.networkSpeedKbps);
  final type = networkLabel(snapshot?.networkType);
  final name = snapshot?.networkName?.trim().toLowerCase();
  if (name == 'unauthorized') {
    return '$type · 需要位置/Wi-Fi 权限读取名称';
  }
  if (name == 'unsupported') {
    return '$type · 系统不支持读取名称';
  }
  if (speed != null) {
    return '$type · $speed';
  }
  return type == '-' ? '等待网络状态' : type;
}

String bluetoothLabel(String? value) {
  final normalized = value?.trim().toLowerCase();
  return switch (normalized) {
    null || '' => '-',
    'on' => '已开启',
    'off' => '已关闭',
    'unauthorized' => '未授权',
    'unsupported' => '不支持',
    'unknown' => '未知',
    _ => value!,
  };
}

String? bluetoothHelper(String? value) {
  final normalized = value?.trim().toLowerCase();
  return switch (normalized) {
    'unauthorized' => '需要附近设备/蓝牙权限',
    'unsupported' => '当前设备或系统不支持',
    'unknown' => '等待系统返回状态',
    null || '' => '等待蓝牙状态',
    _ => null,
  };
}

String locationStatusLabel(DeviceLocation? location) {
  final status = location?.status.trim().toLowerCase();
  return switch (status) {
    'available' => '已定位',
    'unauthorized' => '未授权',
    'disabled' => '定位关闭',
    'unavailable' => '暂无位置',
    'unsupported' => '不支持',
    'unknown' => '未知',
    _ => '等待同步',
  };
}

LatLng? locationPoint(DeviceLocation? location) {
  final latitude = location?.latitude;
  final longitude = location?.longitude;
  if (latitude == null || longitude == null) {
    return null;
  }
  return LatLng(latitude, longitude);
}

Set<Polygon> accuracyPolygons(DeviceLocation location, Color color) {
  final point = locationPoint(location);
  final radius = location.accuracyMeters;
  if (point == null || radius == null || radius <= 0) {
    return const {};
  }
  final latitudeRadians = point.latitude * math.pi / 180;
  final lngMeters = 111320 * math.cos(latitudeRadians).abs().clamp(0.18, 1.0);
  final points = <LatLng>[];
  for (var index = 0; index < 48; index++) {
    final angle = 2 * math.pi * index / 48;
    points.add(
      LatLng(
        point.latitude + (math.sin(angle) * radius / 111320),
        point.longitude + (math.cos(angle) * radius / lngMeters),
      ),
    );
  }
  return {
    Polygon(
      points: points,
      strokeWidth: 2,
      strokeColor: color.withValues(alpha: 0.68),
      fillColor: color.withValues(alpha: 0.12),
    ),
  };
}

String _locationPreviewTitle(DeviceLocation? location) {
  final status = location?.status.trim().toLowerCase();
  return switch (status) {
    'unauthorized' => '对方尚未授权定位',
    'disabled' => '对方定位服务已关闭',
    'unavailable' => '暂时没有可用坐标',
    'available' when AppState.amapAndroidKey.trim().isEmpty => '缺少高德地图 Key',
    'available' => '当前环境暂不支持地图预览',
    _ => '等待实时定位',
  };
}

String _locationPreviewSubtitle(DeviceLocation? location) {
  final status = location?.status.trim().toLowerCase();
  return switch (status) {
    'unauthorized' => '需要对方在系统设置里允许位置权限；恢复后会自动同步最新位置。',
    'disabled' => '需要对方开启系统定位服务，下一次后台或前台同步后这里会更新。',
    'unavailable' => '系统还没有返回有效经纬度；打开对方手机或稍后刷新再试。',
    'available' when AppState.amapAndroidKey.trim().isEmpty =>
      '构建时添加 --dart-define=AMAP_ANDROID_KEY=你的高德AndroidKey 后即可显示地图。',
    'available' => '地图控件仅在 Android/iOS 设备上渲染；当前桌面测试环境显示为降级状态。',
    _ => '对方完成首次同步后，这里会展示地图、精度圈和更新时间。',
  };
}

String locationDetailLabel(DeviceLocation? location) {
  final status = location?.status.trim().toLowerCase();
  if (location == null) {
    return '等待下一次位置状态同步';
  }
  if (status == 'available' &&
      location.latitude != null &&
      location.longitude != null) {
    final accuracy = location.accuracyMeters == null
        ? ''
        : ' · ±${location.accuracyMeters!.round()} 米';
    return '${location.latitude!.toStringAsFixed(6)}, '
        '${location.longitude!.toStringAsFixed(6)} · '
        '${formatRelativeTime(location.capturedAt)}$accuracy';
  }
  return switch (status) {
    'unauthorized' => '需要位置权限后才能共享当前位置',
    'disabled' => '系统定位服务关闭',
    'unavailable' => '系统暂未返回最近位置',
    'unsupported' => '当前平台不支持后台位置共享',
    'unknown' => '等待系统返回定位状态',
    _ => '等待下一次位置状态同步',
  };
}

bool locationNeedsAttention(DeviceLocation? location) {
  final status = location?.status.trim().toLowerCase();
  return status == 'unauthorized' || status == 'disabled';
}

String runtimePlatform() {
  if (Platform.isIOS) return 'ios';
  if (Platform.isAndroid) return 'android';
  return 'android';
}

bool canRenderAmap() {
  if (Platform.isIOS) {
    return true;
  }
  if (!Platform.isAndroid) {
    return false;
  }
  final abi = Abi.current();
  return abi == Abi.androidArm || abi == Abi.androidArm64;
}

String appInitial(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.characters.first.toUpperCase();
}

List<String> unsupportedItems(
    DeviceSnapshot? snapshot, DailyUsageReport? report) {
  return {
    ...?snapshot?.unsupported,
    ...?report?.unsupported,
  }.toList();
}

String capabilityLabel(String value) {
  return switch (value) {
    'native_bridge_unavailable' => '原生桥接暂不可用',
    'usage_report_unavailable' => '使用报告暂不可用',
    _ => value,
  };
}

List<EventSummaryItem> buildEventSummaryItems({
  required List<OperationEvent> allEvents,
  required List<OperationEvent> filteredEvents,
  required EventFilter filter,
}) {
  if (allEvents.isEmpty) {
    return const [];
  }

  final scopedEvents = filteredEvents.isEmpty ? allEvents : filteredEvents;
  final sorted = [...scopedEvents]
    ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  final latest = sorted.first;
  final categoryCounts = {
    for (final candidate in const [
      EventFilter.device,
      EventFilter.network,
      EventFilter.power,
      EventFilter.phone,
    ])
      candidate: scopedEvents
          .where((event) => eventMatchesFilter(event.type, candidate))
          .length,
  };
  final dominant = categoryCounts.entries.reduce(
    (best, next) => next.value > best.value ? next : best,
  );
  final filteredLabel =
      filter == EventFilter.all ? '当前显示全部' : '当前筛选：${eventFilterLabel(filter)}';

  return [
    EventSummaryItem(
      icon: Icons.receipt_long_rounded,
      title: '全部记录',
      value: '${allEvents.length} 条',
      subtitle: '$filteredLabel · ${filteredEvents.length} 条',
      tone: InfoTone.success,
    ),
    EventSummaryItem(
      icon: eventIcon(latest.type),
      title: '最近动态',
      value: eventTitle(latest),
      subtitle:
          '${formatRelativeTime(latest.occurredAt)} · ${platformLabel(latest.platform)}',
    ),
    EventSummaryItem(
      icon: eventFilterIcon(dominant.key),
      title: '主要类别',
      value: eventFilterLabel(dominant.key),
      subtitle:
          '${dominant.value} 条 · ${formatPercent(dominant.value / scopedEvents.length)}',
      tone: dominant.value == 0 ? InfoTone.neutral : InfoTone.success,
    ),
  ];
}

bool eventMatchesFilter(String type, EventFilter filter) {
  return switch (filter) {
    EventFilter.all => true,
    EventFilter.device => type == 'screen_on' ||
        type == 'screen_off' ||
        type == 'boot_completed' ||
        type == 'shutdown_detected',
    EventFilter.network =>
      type == 'network_connected' || type == 'network_disconnected',
    EventFilter.power => type == 'charge_started' || type == 'charge_ended',
    EventFilter.phone => type == 'call_started' || type == 'call_ended',
  };
}

bool eventMatchesQuery(OperationEvent event, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return true;
  }
  final detailsText = event.details?.values
          .map((value) => value.toString().toLowerCase())
          .join(' ') ??
      '';
  return eventTitle(event).toLowerCase().contains(normalized) ||
      eventLabel(event.type).toLowerCase().contains(normalized) ||
      event.type.toLowerCase().contains(normalized) ||
      platformLabel(event.platform).toLowerCase().contains(normalized) ||
      detailsText.contains(normalized);
}

IconData eventFilterIcon(EventFilter filter) {
  return switch (filter) {
    EventFilter.all => Icons.all_inclusive_rounded,
    EventFilter.device => Icons.smartphone_rounded,
    EventFilter.network => Icons.wifi_rounded,
    EventFilter.power => Icons.battery_charging_full_rounded,
    EventFilter.phone => Icons.call_rounded,
  };
}

String eventFilterLabel(EventFilter filter) {
  return switch (filter) {
    EventFilter.all => '全部',
    EventFilter.device => '设备',
    EventFilter.network => '网络',
    EventFilter.power => '电量',
    EventFilter.phone => '通话',
  };
}

IconData eventIcon(String type) {
  return switch (type) {
    'screen_on' => Icons.visibility_rounded,
    'screen_off' => Icons.visibility_off_rounded,
    'boot_completed' => Icons.power_settings_new_rounded,
    'shutdown_detected' => Icons.power_off_rounded,
    'network_connected' => Icons.wifi_rounded,
    'network_disconnected' => Icons.wifi_off_rounded,
    'app_opened' => Icons.open_in_new_rounded,
    'charge_started' => Icons.battery_charging_full_rounded,
    'charge_ended' => Icons.battery_4_bar_rounded,
    'call_started' => Icons.call_rounded,
    'call_ended' => Icons.call_end_rounded,
    _ => Icons.open_in_new_rounded,
  };
}

String eventLabel(String type) {
  return switch (type) {
    'screen_on' => '打开手机',
    'screen_off' => '关闭手机',
    'boot_completed' => '开机完成',
    'shutdown_detected' => '关机',
    'network_connected' => '网络连接',
    'network_disconnected' => '网络断开',
    'app_opened' => '打开应用',
    'charge_started' => '开始充电',
    'charge_ended' => '结束充电',
    'call_started' => '正在打电话',
    'call_ended' => '结束打电话',
    _ => type,
  };
}

String eventTitle(OperationEvent event) {
  if (event.type == 'app_opened') {
    final packageName = eventDetailValue(event, 'packageName');
    final rawAppName = eventDetailValue(event, 'appName');
    final appName = rawAppName != null &&
            (packageName == null ||
                rawAppName.toLowerCase() != packageName.toLowerCase())
        ? rawAppName
        : packageName == null
            ? rawAppName
            : friendlyPackageName(packageName) ?? packageName;
    if (appName != null) {
      return '打开了$appName';
    }
    if (appName != null) {
      return '打开了$appName';
    }
  }
  return eventLabel(event.type);
}

String? eventDetailLine(OperationEvent event) {
  if (event.type == 'app_opened') {
    final appName = eventDetailValue(event, 'appName');
    final packageName = eventDetailValue(event, 'packageName');
    if (packageName != null && packageName != appName) {
      return packageName;
    }
  }
  return null;
}

String? eventDetailValue(OperationEvent event, String key) {
  final value = event.details?[key];
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') {
    return null;
  }
  return text;
}
