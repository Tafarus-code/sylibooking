import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';
import '../auth_controller.dart';
import '../labels.dart';
import '../widgets/role_pill.dart';

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
    final l = L.of(context);
    final username = TextEditingController();
    var role = MerchantRole.staff;

    final added = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l.addSomeone),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: username,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l.username,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<MerchantRole>(
                initialValue: role,
                decoration: InputDecoration(
                  labelText: l.fieldRole,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: MerchantRole.staff,
                    child: Text(l.roleStaffOption),
                  ),
                  DropdownMenuItem(
                    value: MerchantRole.manager,
                    child: Text(l.roleManagerOption),
                  ),
                  DropdownMenuItem(
                    value: MerchantRole.owner,
                    child: Text(l.roleOwnerOption),
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
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.add),
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
      _notify(l.personAdded(username.text.trim()));
      await _load();
    } on ApiException catch (e) {
      if (mounted) _notify(e.message, isError: true);
    } on ApiUnreachableException catch (e) {
      if (mounted) _notify(e.message, isError: true);
    }
  }

  Future<void> _changeRole(Membership member, MerchantRole role) async {
    final l = L.of(context);
    try {
      await widget.auth.api.changeStaffRole(_venueId, member.id, role);
      _notify(l.personIsNowRole(member.username, role.label(l)));
      await _load();
    } on ApiException catch (e) {
      // The server refuses to leave a venue without an owner; say why.
      if (mounted) _notify(e.message, isError: true);
    }
  }

  Future<void> _remove(Membership member) async {
    final l = L.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.removePersonTitle(member.username)),
        content: Text(l.removePersonDetail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.keep),
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

    try {
      await widget.auth.api.removeStaff(_venueId, member.id);
      _notify(l.personRemoved(member.username));
      await _load();
    } on ApiException catch (e) {
      if (mounted) _notify(e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = L.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.whoHasAccess)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add),
        label: Text(l.add),
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
                      child: Text(l.tryAgain),
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
                          title: Row(
                            children: [
                              Flexible(child: Text(member.fullName)),
                              const SizedBox(width: 8),
                              // The role beside the name rather than buried in
                              // the subtitle: it is the reason this list is
                              // being read.
                              RolePill(role: member.role),
                            ],
                          ),
                          subtitle: Text(
                            member.username,
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
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'owner',
                                child: Text(l.makeOwner),
                              ),
                              PopupMenuItem(
                                value: 'manager',
                                child: Text(l.makeManager),
                              ),
                              PopupMenuItem(
                                value: 'staff',
                                child: Text(l.makeStaff),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'remove',
                                child: Text(l.removeAccess),
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
