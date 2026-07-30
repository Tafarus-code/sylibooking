import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../auth_controller.dart';
import '../image_source.dart';

/// The venue's menu.
///
/// Staff see it and can mark items sold out — that is a floor decision taken
/// mid-service. Everything else about an item is owner and manager work, so
/// those controls are absent for staff rather than shown and refused.
class MenuScreen extends StatefulWidget {
  const MenuScreen({
    super.key,
    required this.auth,
    required this.imageSource,
  });

  final AuthController auth;
  final ImageSource imageSource;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  List<MerchantMenuItem> _items = const [];
  bool _loading = true;
  String? _error;
  final Set<int> _busy = {};

  bool get _canEdit => widget.auth.role.canEditProfile;
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
      final items = await widget.auth.api.merchantMenu(_venueId);
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _toggle(MerchantMenuItem item, bool available) async {
    setState(() => _busy.add(item.id));
    try {
      final updated = await widget.auth.api.setMenuItemAvailability(
        _venueId,
        item.id,
        available,
      );
      if (!mounted) return;
      setState(() {
        _items = [
          for (final existing in _items)
            existing.id == updated.id ? updated : existing,
        ];
      });
      _notify(available ? '${item.name} is back on.' : '${item.name} marked sold out.');
    } on ApiException catch (e) {
      if (mounted) _notify(e.message, isError: true);
    } on ApiUnreachableException catch (e) {
      if (mounted) _notify(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  Future<void> _edit({MerchantMenuItem? item}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _MenuItemForm(
        api: widget.auth.api,
        establishmentId: _venueId,
        item: item,
      ),
    );
    if ((saved ?? false) && mounted) await _load();
  }

  Future<void> _pickImage(MerchantMenuItem item) async {
    final picked = await widget.imageSource.pick();
    if (picked == null) return;

    setState(() => _busy.add(item.id));
    try {
      final updated = await widget.auth.api.uploadMenuItemImage(
        establishmentId: _venueId,
        itemId: item.id,
        bytes: picked.bytes,
        filename: picked.filename,
      );
      if (!mounted) return;
      setState(() {
        _items = [
          for (final existing in _items)
            existing.id == updated.id ? updated : existing,
        ];
      });
      _notify('Picture added to ${item.name}.');
    } on ApiException catch (e) {
      if (mounted) _notify(e.message, isError: true);
    } on ApiUnreachableException catch (e) {
      if (mounted) _notify(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  Future<void> _delete(MerchantMenuItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${item.name}?'),
        content: const Text(
          'It disappears from the customer menu. To hide it temporarily, mark '
          'it sold out instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
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
      await widget.auth.api.deleteMenuItem(_venueId, item.id);
      _notify('${item.name} removed.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) _notify(e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Menu')),
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Add item'),
            )
          : null,
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    final theme = Theme.of(context);

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: contentInsets(context, minHorizontal: 32).copyWith(top: 72, bottom: 32),
        children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: _load, child: const Text('Try again')),
        ],
      );
    }

    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: contentInsets(context, minHorizontal: 32).copyWith(top: 72, bottom: 32),
        children: [
          Icon(
            Icons.restaurant_menu,
            size: 56,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No menu yet',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            _canEdit
                ? 'Add your first item and customers will see it straight away.'
                : 'A manager or owner adds items here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    final byCategory = <String, List<MerchantMenuItem>>{};
    for (final item in _items) {
      byCategory.putIfAbsent(item.categoryDisplay, () => []).add(item);
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: contentInsets(context, maxWidth: ContentWidth.list).copyWith(bottom: 88),
      children: [
        if (!_canEdit)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'You can mark items sold out. Adding and editing is done by a '
              'manager or owner.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final entry in byCategory.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              entry.key,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          for (final item in entry.value)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    // A thumbnail when there is one, a placeholder the owner
                    // can tap when there is not.
                    _Thumbnail(
                      item: item,
                      onTap: _canEdit ? () => _pickImage(item) : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              decoration: item.isAvailable
                                  ? null
                                  : TextDecoration.lineThrough,
                            ),
                          ),
                          Text(
                            '${item.price} GNF',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (!item.isAvailable)
                            Text(
                              'Sold out',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Switch(
                      value: item.isAvailable,
                      onChanged: _busy.contains(item.id)
                          ? null
                          : (value) => _toggle(item, value),
                    ),
                    if (_canEdit)
                      PopupMenuButton<String>(
                        onSelected: (choice) => switch (choice) {
                          'edit' => _edit(item: item),
                          'image' => _pickImage(item),
                          _ => _delete(item),
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                          PopupMenuItem(
                            value: 'image',
                            child: Text(
                              item.imageUrl == null
                                  ? 'Add a picture'
                                  : 'Replace picture',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Remove'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// The item's picture, or a tappable placeholder for adding one.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.item, this.onTap});

  final MerchantMenuItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = item.imageUrl;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 56,
          height: 56,
          child: url == null
              ? Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    // Only hint at adding one if this person may.
                    onTap == null
                        ? Icons.restaurant
                        : Icons.add_photo_alternate_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, _, _) => Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Add or edit one item.
class _MenuItemForm extends StatefulWidget {
  const _MenuItemForm({
    required this.api,
    required this.establishmentId,
    this.item,
  });

  final SylibookingApi api;
  final int establishmentId;
  final MerchantMenuItem? item;

  @override
  State<_MenuItemForm> createState() => _MenuItemFormState();
}

class _MenuItemFormState extends State<_MenuItemForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _description =
      TextEditingController(text: widget.item?.description ?? '');
  late final _price = TextEditingController(text: widget.item?.price ?? '');
  late String _category = widget.item?.category ?? 'food';

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final fields = {
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'category': _category,
      'price': _price.text.trim(),
    };

    try {
      if (widget.item == null) {
        await widget.api.createMenuItem(widget.establishmentId, fields);
      } else {
        await widget.api.updateMenuItem(
          widget.establishmentId,
          widget.item!.id,
          fields,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
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
                widget.item == null ? 'Add an item' : 'Edit item',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Give it a name'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'food', child: Text('Food')),
                  DropdownMenuItem(value: 'drink', child: Text('Drink')),
                  DropdownMenuItem(
                    value: 'chicha_flavor',
                    child: Text('Chicha flavour'),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _category = value ?? 'food'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Price (GNF)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return 'Give it a price';
                  if (double.tryParse(text) == null) {
                    return 'Numbers only';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'One-line description (optional)',
                  border: OutlineInputBorder(),
                ),
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
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
