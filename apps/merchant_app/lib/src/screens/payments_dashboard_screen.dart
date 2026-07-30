import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

import '../auth_controller.dart';

/// What the venue took, what is still owed, and who to chase.
class PaymentsDashboardScreen extends StatefulWidget {
  const PaymentsDashboardScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<PaymentsDashboardScreen> createState() =>
      _PaymentsDashboardScreenState();
}

enum DashboardWindow {
  week('7 days', 6),
  month('30 days', 29),
  quarter('90 days', 89);

  const DashboardWindow(this.label, this.daysBack);

  final String label;
  final int daysBack;
}

class _PaymentsDashboardScreenState extends State<PaymentsDashboardScreen> {
  DashboardWindow _window = DashboardWindow.month;
  PaymentDashboard? _dashboard;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    try {
      final dashboard = await widget.auth.api.paymentDashboard(
        establishmentId: widget.auth.selectedVenueId!,
        from: today.subtract(Duration(days: _window.daysBack)),
        to: today,
      );
      if (!mounted) return;
      setState(() {
        _dashboard = dashboard;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        await widget.auth.signOut();
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } on ApiUnreachableException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: 'Refresh',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<DashboardWindow>(
              segments: [
                for (final window in DashboardWindow.values)
                  ButtonSegment(value: window, label: Text(window.label)),
              ],
              selected: {_window},
              onSelectionChanged: (selection) {
                setState(() => _window = selection.first);
                _load();
              },
            ),
          ),
        ),
      ),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final theme = Theme.of(context);

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: contentInsets(context, minHorizontal: 32).copyWith(top: 72, bottom: 32),
        children: [
          Icon(Icons.cloud_off, size: 56, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(onPressed: _load, child: const Text('Try again')),
        ],
      );
    }

    final dashboard = _dashboard!;

    return ListView(
      key: const Key('payments-dashboard-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: contentInsets(context, maxWidth: ContentWidth.list, minHorizontal: 12).copyWith(top: 12, bottom: 32),
      children: [
        Text(
          '${DateFormat.MMMd().format(dashboard.from)} – '
          '${DateFormat.MMMd().format(dashboard.to)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),

        // Collected first and largest: it is the number a merchant opens this
        // screen to see.
        _MoneyCard(
          label: 'Collected',
          amount: dashboard.collected,
          detail: '${dashboard.completedCount} '
              '${dashboard.completedCount == 1 ? "payment" : "payments"}',
          icon: Icons.check_circle,
          tone: _Tone.good,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _MoneyCard(
                label: 'Awaiting',
                amount: dashboard.awaiting,
                detail: '${dashboard.pendingCount} pending',
                icon: Icons.hourglass_top,
                tone: dashboard.pendingCount > 0 ? _Tone.warn : _Tone.neutral,
                compact: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MoneyCard(
                label: 'Failed',
                amount: dashboard.failed,
                detail: '${dashboard.failedCount} failed',
                icon: Icons.error_outline,
                tone: dashboard.failedCount > 0 ? _Tone.bad : _Tone.neutral,
                compact: true,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),
        _SectionLabel('Bookings'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _CountRow('Total', dashboard.totalReservations),
                _CountRow('Pending', dashboard.reservationCounts['pending'] ?? 0),
                _CountRow(
                  'Confirmed',
                  dashboard.reservationCounts['confirmed'] ?? 0,
                ),
                _CountRow(
                  'Cancelled',
                  dashboard.reservationCounts['cancelled'] ?? 0,
                ),
                _CountRow(
                  'Completed',
                  dashboard.reservationCounts['completed'] ?? 0,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        _SectionLabel('By payment method'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final row in dashboard.byProvider)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(row.providerDisplay),
                              Text(
                                '${row.bookings} '
                                '${row.bookings == 1 ? "booking" : "bookings"}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              row.provider == 'cash_on_arrival'
                                  ? '—'
                                  : '${row.collected} GNF',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (row.provider == 'cash_on_arrival')
                              Text(
                                'at the till',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        _SectionLabel('Needs chasing'),
        if (dashboard.needsAttention.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Nothing outstanding. Every booking is settled.'),
                  ),
                ],
              ),
            ),
          )
        else
          for (final item in dashboard.needsAttention)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      item.paymentStatus == PaymentStatus.failed
                          ? Icons.error
                          : Icons.hourglass_top,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.customerName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                          Text(
                            '${DateFormat.MMMEd().format(item.dateTime)} '
                            '${DateFormat.Hm().format(item.dateTime)} · '
                            '${item.spaceName}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                          Text(
                            item.paymentStatus == PaymentStatus.failed
                                ? '${item.paymentProviderDisplay} payment failed'
                                : '${item.paymentProviderDisplay} not received',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

enum _Tone { good, warn, bad, neutral }

class _MoneyCard extends StatelessWidget {
  const _MoneyCard({
    required this.label,
    required this.amount,
    required this.detail,
    required this.icon,
    required this.tone,
    this.compact = false,
  });

  final String label;
  final String amount;
  final String detail;
  final IconData icon;
  final _Tone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final (background, foreground) = switch (tone) {
      _Tone.good => (scheme.primaryContainer, scheme.onPrimaryContainer),
      _Tone.warn => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      _Tone.bad => (scheme.errorContainer, scheme.onErrorContainer),
      _Tone.neutral => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
    };

    return Card(
      color: background,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '$amount GNF',
                style: (compact
                        ? theme.textTheme.titleMedium
                        : theme.textTheme.headlineSmall)
                    ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow(this.label, this.count);

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              '$count',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );
}
