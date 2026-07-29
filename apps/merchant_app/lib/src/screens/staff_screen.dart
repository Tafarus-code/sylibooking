import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../auth_controller.dart';

/// Who has access to this venue, and in what capacity.
///
/// Owner-only. A manager reaching this screen would be refused by the server,
/// so the entry point is not offered to them at all.
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  List<Membership> _members = const [];
  bool _loading = true;
  String? _error;

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
      final members = await widget.auth.api.merchantStaff(_venueId);
      if (!mounted) return;
      setState(() {
        _members = members;
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

  Future<void> _add() async {
    final username = TextEditingController();
    var role = MerchantRole.staff;

    final added = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add someone'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: username,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<MerchantRole>(
                initialValue: role,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: MerchantRole.staff,
                    child: Text('Staff — floor work'),
                  ),
                  DropdownMenuItem(
                    value: MerchantRole.manager,
                    child: Text('Manager — venue and profile'),
                  ),
                  DropdownMenuItem(
                    value: MerchantRole.owner,
                    child: Text('Owner — everything'),
                  ),
                ],
                onChanged: (value) => setDialogState(
                  () => role = value ?? MerchantRole.staff,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (!(added ?? false)) return;

    try {
      await widget.auth.api.addStaff(
        _venueId,
        username: username.text.trim(),
        role: role,
      );
      _notify('${username.text.trim()} added.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) _notify(e.message, isError: true);
    } on ApiUnreachableException catch (e) {
      if (mounted) _notify(e.message, isError: true);
    }
  }

  Future<void> _changeRole(Membership member, MerchantRole role) async {
    try {
      await widget.auth.api.changeStaffRole(_venueId, member.id, role);
      _notify('${member.username} is now ${role.name}.');
      await _load();
    } on ApiException catch (e) {
      // The server refuses to leave a venue without an owner; say why.
      if (mounted) _notify(e.message, isError: true);
    }
  }

  Future<void> _remove(Membership member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${member.username}?'),
        content: const Text('They lose access to this venue immediately.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    try {
      await widget.auth.api.removeStaff(_venueId, member.id);
      _notify('${member.username} removed.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) _notify(e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Who has access')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add),
        label: const Text('Add'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(32, 72, 32, 32),
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    for (final member in _members)
                      Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: ListTile(
                          title: Text(member.fullName),
                          subtitle: Text(
                            '${member.username} · ${member.roleDisplay}',
                            style: theme.textTheme.bodySmall,
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (choice) => switch (choice) {
                              'remove' => _remove(member),
                              _ => _changeRole(
                                  member,
                                  MerchantRole.parse(choice),
                                ),
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'owner',
                                child: Text('Make owner'),
                              ),
                              PopupMenuItem(
                                value: 'manager',
                                child: Text('Make manager'),
                              ),
                              PopupMenuItem(
                                value: 'staff',
                                child: Text('Make staff'),
                              ),
                              PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'remove',
                                child: Text('Remove access'),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
