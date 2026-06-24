import 'package:flutter/material.dart';

import 'app_state.dart';
import 'models.dart';

void main() {
  runApp(const MutualWatchApp());
}

class MutualWatchApp extends StatefulWidget {
  const MutualWatchApp({super.key});

  @override
  State<MutualWatchApp> createState() => _MutualWatchAppState();
}

class _MutualWatchAppState extends State<MutualWatchApp> {
  late final AppState state;

  @override
  void initState() {
    super.initState();
    state = AppState()..bootstrap();
  }

  @override
  void dispose() {
    state.dispose();
    super.dispose();
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
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF0F8A8A),
                brightness: Brightness.light,
              ),
              useMaterial3: true,
            ),
            home: state.loading && state.user == null
                ? const LoadingScreen()
                : state.user == null
                    ? const AuthScreen()
                    : const HomeShell(),
          );
        },
      ),
    );
  }
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
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                const SizedBox(height: 24),
                Icon(Icons.link_rounded, size: 52, color: theme.colorScheme.primary),
                const SizedBox(height: 20),
                Text(
                  'Mutual Watch',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 28),
                SegmentedButton<AuthMode>(
                  segments: const [
                    ButtonSegment(value: AuthMode.login, label: Text('登录'), icon: Icon(Icons.login_rounded)),
                    ButtonSegment(value: AuthMode.register, label: Text('注册'), icon: Icon(Icons.person_add_rounded)),
                  ],
                  selected: {mode},
                  onSelectionChanged: (value) => setState(() => mode = value.first),
                ),
                const SizedBox(height: 18),
                if (mode == AuthMode.register)
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: '昵称',
                      prefixIcon: Icon(Icons.badge_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                if (mode == AuthMode.register) const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: '手机号',
                    prefixIcon: Icon(Icons.phone_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '密码',
                    prefixIcon: Icon(Icons.lock_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: state.loading ? null : _submit,
                  icon: state.loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(mode == AuthMode.login ? Icons.arrow_forward_rounded : Icons.check_rounded),
                  label: Text(mode == AuthMode.login ? '进入' : '创建账号'),
                ),
                if (state.error != null) ErrorBanner(message: state.error!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final state = AppScope.of(context);
    if (mode == AuthMode.login) {
      await state.login(phoneController.text.trim(), passwordController.text);
    } else {
      await state.register(nameController.text.trim(), phoneController.text.trim(), passwordController.text);
    }
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pages = [
      const DashboardTab(),
      const PairingTab(),
      const AppUsageTab(),
      const EventsTab(),
      const PrivacyTab(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(state.partner == null ? 'Mutual Watch' : state.partner!.displayName),
        actions: [
          IconButton(
            tooltip: '同步',
            onPressed: state.syncing
                ? null
                : () async {
                    await state.syncTelemetry();
                    await state.refreshPartner();
                  },
            icon: state.syncing
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_rounded), label: '总览'),
          NavigationDestination(icon: Icon(Icons.qr_code_2_rounded), label: '绑定'),
          NavigationDestination(icon: Icon(Icons.apps_rounded), label: '应用'),
          NavigationDestination(icon: Icon(Icons.timeline_rounded), label: '记录'),
          NavigationDestination(icon: Icon(Icons.privacy_tip_rounded), label: '隐私'),
        ],
      ),
    );
  }
}

class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final snapshot = state.overview?.latestSnapshot;
    final report = state.overview?.dailyReport;
    return RefreshIndicator(
      onRefresh: state.refreshPartner,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (state.error != null) ErrorBanner(message: state.error!),
          if (state.partner == null)
            const EmptyPanel(
              icon: Icons.link_off_rounded,
              title: '未绑定',
              subtitle: '在绑定页创建或输入邀请码',
            )
          else ...[
            SectionHeader(
              title: state.partner!.displayName,
              trailing: state.overview?.partner.sharingPaused == true ? '已暂停' : '共享中',
            ),
            const SizedBox(height: 12),
            MetricsGrid(
              metrics: [
                MetricData('屏幕时间', formatDuration(report?.screenTimeMs ?? 0), Icons.smartphone_rounded),
                MetricData('使用次数', '${report?.pickupCount ?? 0}', Icons.touch_app_rounded),
                MetricData('首次使用', formatTime(report?.firstUseAt), Icons.wb_twilight_rounded),
                MetricData('最长连续', formatDuration(report?.longestContinuousMs ?? 0), Icons.timer_rounded),
              ],
            ),
            const SizedBox(height: 18),
            SectionHeader(title: '手机状态'),
            const SizedBox(height: 12),
            StatusGrid(snapshot: snapshot),
            const SizedBox(height: 18),
            SectionHeader(title: '最近操作'),
            const SizedBox(height: 10),
            ...state.overview!.latestEvents.map((event) => EventTile(event: event)),
            if (state.overview!.latestEvents.isEmpty)
              const EmptyPanel(icon: Icons.inbox_rounded, title: '暂无记录', subtitle: '等待下一次同步'),
          ],
        ],
      ),
    );
  }
}

class PairingTab extends StatefulWidget {
  const PairingTab({super.key});

  @override
  State<PairingTab> createState() => _PairingTabState();
}

class _PairingTabState extends State<PairingTab> {
  final codeController = TextEditingController();

  @override
  void dispose() {
    codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (state.error != null) ErrorBanner(message: state.error!),
        SectionHeader(title: '当前绑定'),
        const SizedBox(height: 12),
        InfoCard(
          icon: state.partner == null ? Icons.person_off_rounded : Icons.favorite_rounded,
          title: state.partner?.displayName ?? '未绑定',
          subtitle: state.partner == null ? '一个账号同一时间只能绑定一个对象' : '双方均可随时暂停共享或解绑',
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: state.partner == null ? state.createInvite : null,
          icon: const Icon(Icons.qr_code_rounded),
          label: const Text('生成邀请码'),
        ),
        if (state.inviteCode != null) ...[
          const SizedBox(height: 14),
          Center(
            child: SelectableText(
              state.inviteCode!,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
        const SizedBox(height: 18),
        TextField(
          controller: codeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: '邀请码',
            prefixIcon: Icon(Icons.password_rounded),
            border: OutlineInputBorder(),
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: state.partner == null ? () => state.acceptInvite(codeController.text.trim()) : null,
          icon: const Icon(Icons.link_rounded),
          label: const Text('确认绑定'),
        ),
        if (state.partner != null) ...[
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: state.unpair,
            icon: const Icon(Icons.link_off_rounded),
            label: const Text('解除绑定'),
          ),
        ],
      ],
    );
  }
}

class AppUsageTab extends StatelessWidget {
  const AppUsageTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final usage = state.appUsage;
    return RefreshIndicator(
      onRefresh: state.refreshPartner,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(title: '今日应用'),
          const SizedBox(height: 10),
          if (usage.isEmpty)
            const EmptyPanel(icon: Icons.apps_outage_rounded, title: '暂无应用记录', subtitle: 'Android 授权后会显示明细')
          else
            ...usage.map((item) => AppUsageTile(session: item)),
        ],
      ),
    );
  }
}

class EventsTab extends StatelessWidget {
  const EventsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return RefreshIndicator(
      onRefresh: state.refreshPartner,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(title: '操作详情'),
          const SizedBox(height: 10),
          if (state.events.isEmpty)
            const EmptyPanel(icon: Icons.history_rounded, title: '暂无操作记录', subtitle: '同步后会显示状态变化')
          else
            ...state.events.map((event) => EventTile(event: event)),
        ],
      ),
    );
  }
}

class PrivacyTab extends StatelessWidget {
  const PrivacyTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final user = state.user!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (state.error != null) ErrorBanner(message: state.error!),
        SectionHeader(title: user.displayName),
        const SizedBox(height: 12),
        SwitchListTile(
          value: user.sharingPaused,
          onChanged: state.setSharingPaused,
          title: const Text('暂停共享'),
          secondary: const Icon(Icons.pause_circle_rounded),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        const SizedBox(height: 12),
        InfoCard(
          icon: state.usageAccessGranted ? Icons.verified_rounded : Icons.warning_rounded,
          title: state.usageAccessGranted ? '使用情况权限已可用' : '使用情况权限未开启',
          subtitle: 'Android 需要用户手动授权',
          action: TextButton.icon(
            onPressed: state.openUsageAccessSettings,
            icon: const Icon(Icons.settings_rounded),
            label: const Text('设置'),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: state.deleteMyData,
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('删除我的数据'),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: state.logout,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('退出登录'),
        ),
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, this.trailing, super.key});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null)
          Chip(
            label: Text(trailing!),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

class MetricsGrid extends StatelessWidget {
  const MetricsGrid({required this.metrics, super.key});

  final List<MetricData> metrics;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: metrics.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.85,
      ),
      itemBuilder: (context, index) {
        final metric = metrics[index];
        return Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(metric.icon, size: 22),
                Text(metric.value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                Text(metric.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        );
      },
    );
  }
}

class StatusGrid extends StatelessWidget {
  const StatusGrid({this.snapshot, super.key});

  final DeviceSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final items = [
      MetricData('电量', snapshot?.batteryPercent == null ? '-' : '${snapshot!.batteryPercent}%', Icons.battery_5_bar_rounded),
      MetricData('音量', snapshot?.volumePercent == null ? '-' : '${snapshot!.volumePercent}%', Icons.volume_up_rounded),
      MetricData('网络', snapshot?.networkType ?? '-', Icons.wifi_rounded),
      MetricData('蓝牙', snapshot?.bluetoothState ?? '-', Icons.bluetooth_rounded),
      MetricData('WiFi流量', formatBytes(snapshot?.wifiBytesToday), Icons.router_rounded),
      MetricData('数据流量', formatBytes(snapshot?.mobileBytesToday), Icons.signal_cellular_alt_rounded),
      MetricData('机型', snapshot?.model ?? '-', Icons.phone_android_rounded),
      MetricData('存储', formatStorage(snapshot), Icons.storage_rounded),
    ];
    return MetricsGrid(metrics: items);
  }
}

class MetricData {
  const MetricData(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}

class InfoCard extends StatelessWidget {
  const InfoCard({
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
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: Icon(icon),
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
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(subtitle, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class AppUsageTile extends StatelessWidget {
  const AppUsageTile({required this.session, super.key});

  final AppUsageSession session;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: ListTile(
          leading: const Icon(Icons.apps_rounded),
          title: Text(session.appName ?? session.packageName, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${formatTime(session.startedAt)} - ${formatTime(session.endedAt)}'),
          trailing: Text(formatDuration(session.durationMs)),
        ),
      ),
    );
  }
}

class EventTile extends StatelessWidget {
  const EventTile({required this.event, super.key});

  final OperationEvent event;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: ListTile(
          leading: Icon(eventIcon(event.type)),
          title: Text(eventLabel(event.type)),
          subtitle: Text(formatTime(event.occurredAt)),
        ),
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: colors.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatDuration(int milliseconds) {
  final minutes = (milliseconds / 60000).round();
  if (minutes < 60) return '$minutes 分钟';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分钟';
}

String formatTime(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final value = DateTime.tryParse(iso)?.toLocal();
  if (value == null) return '-';
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String formatBytes(int? bytes) {
  if (bytes == null) return '-';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}

String formatStorage(DeviceSnapshot? snapshot) {
  if (snapshot?.storageUsedBytes == null || snapshot?.storageTotalBytes == null) return '-';
  return '${formatBytes(snapshot!.storageUsedBytes)} / ${formatBytes(snapshot.storageTotalBytes)}';
}

IconData eventIcon(String type) {
  return switch (type) {
    'screen_on' => Icons.visibility_rounded,
    'screen_off' => Icons.visibility_off_rounded,
    'boot_completed' => Icons.power_settings_new_rounded,
    'shutdown_detected' => Icons.power_off_rounded,
    'network_connected' => Icons.wifi_rounded,
    'network_disconnected' => Icons.wifi_off_rounded,
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
