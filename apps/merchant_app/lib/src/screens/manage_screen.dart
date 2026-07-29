import 'package:flutter/material.dart';

import '../auth_controller.dart';
import '../image_source.dart';
import 'hours_screen.dart';
import 'menu_screen.dart';
import 'photos_screen.dart';
import 'profile_screen.dart';
import 'staff_screen.dart';

/// The way in to everything about the venue itself.
///
/// Entries a role cannot use are absent rather than shown and refused — the
/// server rejects them either way, but a button that always fails is a lie.
/// The menu is the exception: staff belong there to mark items sold out.
class ManageScreen extends StatelessWidget {
  const ManageScreen({
    super.key,
    required this.auth,
    required this.imageSource,
  });

  final AuthController auth;
  final ImageSource imageSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final role = auth.role;
    final venue = auth.selectedVenue;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage'),
        actions: [
          if (auth.hasMultipleVenues)
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Switch venue',
              onPressed: auth.changeVenue,
            ),
        ],
      ),
      body: ListView(
        children: [
          if (venue != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(venue.name, style: theme.textTheme.titleLarge),
                  Text(
                    '${venue.city} · you are ${venue.roleDisplay.toLowerCase()}'
                    ' here',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(),

          // Staff can reach the menu: marking a dish sold out is theirs to do.
          _Entry(
            icon: Icons.restaurant_menu,
            title: 'Menu',
            subtitle: role.canEditProfile
                ? 'Items, prices, and what is sold out'
                : 'Mark items sold out',
            onTap: () => _open(
              context,
              MenuScreen(auth: auth, imageSource: imageSource),
            ),
          ),

          // Everyone may look at the photos; only owners and managers add.
          _Entry(
            icon: Icons.photo_library_outlined,
            title: 'Photos',
            subtitle: role.canEditProfile
                ? 'What customers see of the room'
                : 'What customers see of the room (view only)',
            onTap: () => _open(
              context,
              PhotosScreen(auth: auth, imageSource: imageSource),
            ),
          ),

          if (role.canEditProfile) ...[
            _Entry(
              icon: Icons.schedule,
              title: 'Opening hours',
              subtitle: 'When the doors are open, including past midnight',
              onTap: () => _open(context, HoursScreen(auth: auth)),
            ),
            _Entry(
              icon: Icons.storefront,
              title: 'Venue details',
              subtitle: 'Name, tagline, description, address',
              onTap: () => _open(context, ProfileScreen(auth: auth)),
            ),
          ],

          if (role.canManageStaff)
            _Entry(
              icon: Icons.people_outline,
              title: 'Who has access',
              subtitle: 'Add people, change roles, remove access',
              onTap: () => _open(context, StaffScreen(auth: auth)),
            ),

          if (!role.canEditProfile)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Opening hours, venue details and access are managed by an '
                'owner or manager.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),

          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text(
              'Sign out',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: auth.signOut,
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );
}
