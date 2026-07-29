import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../auth_controller.dart';

const _dayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Editing the week's opening hours.
///
/// The week is saved as a unit, matching the API: seven separate saves would
/// leave the venue in states it was never meant to be in halfway through.
class HoursScreen extends StatefulWidget {
  const HoursScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<HoursScreen> createState() => _HoursScreenState();
}

class _DayDraft {
  _DayDraft({required this.isClosed, this.opens, this.closes});

  bool isClosed;
  TimeOfDay? opens;
  TimeOfDay? closes;
}

class _HoursScreenState extends State<HoursScreen> {
  final List<_DayDraft> _week = [
    for (var day = 0; day < 7; day++) _DayDraft(isClosed: true),
  ];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _canEdit => widget.auth.role.canEditProfile;
  int get _venueId => widget.auth.selectedVenueId!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  TimeOfDay? _parse(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length < 2) return null;
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  String _format(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.auth.api.merchantHours(_venueId);
      if (!mounted) return;
      setState(() {
        for (final row in rows) {
          if (row.dayOfWeek < 0 || row.dayOfWeek > 6) continue;
          _week[row.dayOfWeek] = _DayDraft(
            isClosed: row.isClosed,
            opens: _parse(row.opens),
            closes: _parse(row.closes),
          );
        }
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
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

  Future<void> _pick(int day, {required bool opening}) async {
    final draft = _week[day];
    final initial = (opening ? draft.opens : draft.closes) ??
        const TimeOfDay(hour: 18, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      if (opening) {
        draft.opens = picked;
      } else {
        draft.closes = picked;
      }
    });
  }

  Future<void> _save() async {
    // Mirrors the server: a day that is open needs both times.
    for (var day = 0; day < 7; day++) {
      final draft = _week[day];
      if (!draft.isClosed && (draft.opens == null || draft.closes == null)) {
        setState(() {
          _error = '${_dayNames[day]} is open but has no times set.';
        });
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final payload = [
      for (var day = 0; day < 7; day++)
        {
          'day_of_week': day,
          'is_closed': _week[day].isClosed,
          'opens': _week[day].isClosed ? null : _format(_week[day].opens!),
          'closes': _week[day].isClosed ? null : _format(_week[day].closes!),
        },
    ];

    try {
      await widget.auth.api.replaceHours(_venueId, payload);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Hours saved.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    } on ApiUnreachableException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Opening hours')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (!_canEdit)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Only an owner or manager can change opening hours.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                for (var day = 0; day < 7; day++) _dayRow(day),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                if (_canEdit)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save week'),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _dayRow(int day) {
    final theme = Theme.of(context);
    final draft = _week[day];
    final overnight = !draft.isClosed &&
        draft.opens != null &&
        draft.closes != null &&
        (draft.closes!.hour * 60 + draft.closes!.minute) <=
            (draft.opens!.hour * 60 + draft.opens!.minute);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text(_dayNames[day])),
                Text(
                  draft.isClosed ? 'Closed' : 'Open',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Switch(
                  value: !draft.isClosed,
                  onChanged: _canEdit
                      ? (open) => setState(() => draft.isClosed = !open)
                      : null,
                ),
              ],
            ),
            if (!draft.isClosed)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _canEdit ? () => _pick(day, opening: true) : null,
                      child: Text(
                        draft.opens == null
                            ? 'Opens'
                            : 'Opens ${_format(draft.opens!)}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _canEdit ? () => _pick(day, opening: false) : null,
                      child: Text(
                        draft.closes == null
                            ? 'Closes'
                            : 'Closes ${_format(draft.closes!)}',
                      ),
                    ),
                  ),
                ],
              ),
            if (overnight)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Runs past midnight into the next morning.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
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
