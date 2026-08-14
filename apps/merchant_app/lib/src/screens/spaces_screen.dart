import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';
import '../auth_controller.dart';

/// The venue's seating plan: what a customer can actually book.
///
/// Grouped by kind rather than listed flat, because a merchant thinks in
/// "my tables, my VIP rooms, my terrace" and a room with twenty tables reads
/// as a wall otherwise.
///
/// Owner and manager only. Staff can read the layout over the API — the desk
/// names the table a booking is on — but there is nothing here they may
/// change, so the entry is absent for them rather than shown and refused.
class SpacesScreen extends StatefulWidget {
  const SpacesScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<SpacesScreen> createState() => _SpacesScreenState();
}

class _SpacesScreenState extends State<SpacesScreen> {
  List<Space> _spaces = const [];
  bool _loading = true;
  String? _error;
  final Set<int> _busy = {};

  int get _venueId => widget.auth.selectedVenueId!;

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
    try {
      final spaces = await widget.auth.api.merchantSpaces(_venueId);
      if (!mounted) return;
      setState(() {
        _spaces = spaces;
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

  void _notify(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  Future<void> _edit({Space? space}) async {
    final saved = await showModalBottomSheet<Space>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SpaceForm(
        api: widget.auth.api,
        establishmentId: _venueId,
        space: space,
      ),
    );
    if (saved == null || !mounted) return;
    _notify(L.of(context).spaceSaved(saved.name));
    await _load();
  }

  Future<void> _remove(Space space) async {
    final l = L.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.removeSpaceTitle(space.name)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.removeSpaceDetail),
            const SizedBox(height: 8),
            // Said before the tap, not after: a merchant clearing out an old
            // table deserves to know the bookings on it survive.
            Text(
              l.removeSpaceKeepsHistory,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.keepIt),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l.remove),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    setState(() => _busy.add(space.id));
    try {
      final retired = await widget.auth.api.removeSpace(_venueId, space.id);
      // Null means the row is gone; a space back means it was kept because
      // something was booked on it. Only the server knows which.
      _notify(
        retired == null
            ? l.spaceDeleted(space.name)
            : l.spaceRetiredNotice(space.name),
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) _notify(e.message, isError: true);
    } on ApiUnreachableException catch (e) {
      if (mounted) _notify(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy.remove(space.id));
    }
  }

  Future<void> _bringBack(Space space) async {
    final l = L.of(context);
    setState(() => _busy.add(space.id));
    try {
      await widget.auth.api.updateSpace(_venueId, space.id, {
        'is_active': true,
      });
      _notify(l.spaceBroughtBack(space.name));
      await _load();
    } on ApiException catch (e) {
      if (mounted) _notify(e.message, isError: true);
    } on ApiUnreachableException catch (e) {
      if (mounted) _notify(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy.remove(space.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    // Staff read the room; owners and managers change it. The server draws
    // the same line, so a hidden button here is the interface agreeing with
    // the rule rather than the only thing enforcing it.
    final canEdit = widget.auth.role.canEditProfile;

    return Scaffold(
      appBar: AppBar(title: Text(l.tablesAndRooms)),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: Text(l.addSpace),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: _body(l, canEdit: canEdit),
      ),
    );
  }

  Widget _body(L l, {required bool canEdit}) {
    final theme = Theme.of(context);

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: contentInsets(context, minHorizontal: 32)
            .copyWith(top: 72, bottom: 32),
        children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: _load, child: Text(l.tryAgain)),
        ],
      );
    }

    if (_spaces.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: contentInsets(context, minHorizontal: 32)
            .copyWith(top: 72, bottom: 32),
        children: [
          Icon(
            Icons.table_restaurant_outlined,
            size: 56,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            l.noSpacesYet,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            l.noSpacesDetail,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    // Kept in the enum's own order so the groups do not reshuffle as spaces
    // are added.
    final byType = <SpaceType, List<Space>>{};
    for (final space in _spaces) {
      byType.putIfAbsent(space.type, () => []).add(space);
    }
    final types = SpaceType.values.where(byType.containsKey);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: contentInsets(context, maxWidth: ContentWidth.list)
          .copyWith(bottom: 88),
      children: [
        for (final type in types) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              _typeLabel(l, type),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          for (final space in byType[type]!)
            _SpaceRow(
              space: space,
              canEdit: canEdit,
              busy: _busy.contains(space.id),
              onEdit: () => _edit(space: space),
              onRemove: () => _remove(space),
              onBringBack: () => _bringBack(space),
            ),
        ],
      ],
    );
  }
}

String _typeLabel(L l, SpaceType type) => switch (type) {
      SpaceType.table => l.spaceTypeTable,
      SpaceType.vipRoom => l.spaceTypeVipRoom,
      SpaceType.terrace => l.spaceTypeTerrace,
      SpaceType.unknown => l.statusUnknown,
    };

class _SpaceRow extends StatelessWidget {
  const _SpaceRow({
    required this.space,
    required this.canEdit,
    required this.busy,
    required this.onEdit,
    required this.onRemove,
    required this.onBringBack,
  });

  final Space space;

  /// Whether this account may change the room, rather than only read it.
  final bool canEdit;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final VoidCallback onBringBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = L.of(context);

    // Dimmed rather than struck through or hidden. A retired space is still
    // part of the room — its bookings are still on the books — and the
    // merchant who retired it needs to find it again to bring it back.
    //
    // No type tag on the card, though the design file draws one: its list is
    // flat, so the tag is the only thing saying what kind of space this is.
    // Ours is grouped under a heading that already says it, and the same
    // word twice on one row is noise rather than reassurance.
    return Opacity(
      opacity: space.isActive ? 1 : 0.45,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 11, 8, 11),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      space.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      space.isActive
                          ? l.spaceSeats(space.capacity)
                          // Says what retiring actually did, on the row
                          // itself: the bookings did not go anywhere.
                          : l.spaceRetiredKeepsBookings,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!canEdit)
                const SizedBox.shrink()
              else if (space.isActive)
                PopupMenuButton<String>(
                  enabled: !busy,
                  onSelected: (choice) =>
                      choice == 'edit' ? onEdit() : onRemove(),
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'edit', child: Text(l.editSpace)),
                    PopupMenuItem(value: 'remove', child: Text(l.remove)),
                  ],
                )
              else
                TextButton(
                  onPressed: busy ? null : onBringBack,
                  child: Text(l.bringSpaceBack),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add or edit one space.
class _SpaceForm extends StatefulWidget {
  const _SpaceForm({
    required this.api,
    required this.establishmentId,
    this.space,
  });

  final SylibookingApi api;
  final int establishmentId;
  final Space? space;

  @override
  State<_SpaceForm> createState() => _SpaceFormState();
}

class _SpaceFormState extends State<_SpaceForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.space?.name ?? '');
  late final _capacity = TextEditingController(
    text: widget.space == null ? '' : '${widget.space!.capacity}',
  );
  late SpaceType _type = widget.space?.type ?? SpaceType.table;

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _capacity.dispose();
    super.dispose();
  }

  String _typeValue(SpaceType type) => switch (type) {
        SpaceType.vipRoom => 'vip_room',
        SpaceType.terrace => 'terrace',
        _ => 'table',
      };

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final fields = {
      'name': _name.text.trim(),
      'type': _typeValue(_type),
      'capacity': int.parse(_capacity.text.trim()),
    };

    try {
      final saved = widget.space == null
          ? await widget.api.createSpace(widget.establishmentId, fields)
          : await widget.api.updateSpace(
              widget.establishmentId,
              widget.space!.id,
              fields,
            );
      if (!mounted) return;
      Navigator.pop(context, saved);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        // The duplicate-name case arrives on the field, and reads better
        // there than as a generic failure at the bottom of the sheet.
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
    final l = L.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.space == null ? l.addSpace : l.editSpace,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: l.spaceName,
                  hintText: l.spaceNameHint,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? l.giveItAName
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SpaceType>(
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: l.spaceType,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: SpaceType.table,
                    child: Text(l.spaceTypeTable),
                  ),
                  DropdownMenuItem(
                    value: SpaceType.vipRoom,
                    child: Text(l.spaceTypeVipRoom),
                  ),
                  DropdownMenuItem(
                    value: SpaceType.terrace,
                    child: Text(l.spaceTypeTerrace),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) =>
                        setState(() => _type = value ?? SpaceType.table),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _capacity,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l.spaceCapacity,
                  hintText: l.spaceCapacityHint,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  final seats = int.tryParse(text);
                  if (seats == null) return l.numbersOnly;
                  // Mirrors the server rather than trusting it: a zero-seat
                  // table is a 400 that did not need a round trip.
                  if (seats < 1) return l.seatsAtLeastOne;
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l.save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
