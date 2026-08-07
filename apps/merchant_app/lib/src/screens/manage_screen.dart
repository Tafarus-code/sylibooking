import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';
import '../auth_controller.dart';
import '../image_source.dart';
import '../labels.dart';
import '../widgets/language_toggle.dart';
import 'branding_screen.dart';
import 'hours_screen.dart';
import 'menu_screen.dart';
import 'photos_screen.dart';
import 'spaces_screen.dart';
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
    required this.localeController,
  });

  final AuthController auth;
  final ImageSource imageSource;
  final LocaleController localeController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = L.of(context);
    final role = auth.role;
    final venue = auth.selectedVenue;

    // Grid on a tablet, list on a phone. The entries are the same set either
    // way — role gating builds the list once, above the layout, so a wide
    // screen can never show a staff account something a narrow one hides.
    final asTiles = !LayoutSize.of(context).isCompact;

    final entries = <Widget>[
          // Staff can reach the menu: marking a dish sold out is theirs to do.
          _Entry(
            tile: asTiles,
            icon: Icons.restaurant_menu,
            title: l.menu,
            subtitle: role.canEditProfile
                ? l.menuSubtitleEdit
                : l.menuSubtitleStaff,
            onTap: () => _open(
              context,
              MenuScreen(auth: auth, imageSource: imageSource),
            ),
          ),

          // Everyone may look at the photos; only owners and managers add.
          _Entry(
            tile: asTiles,
            icon: Icons.photo_library_outlined,
            title: l.photos,
            subtitle: role.canEditProfile
                ? l.photosSubtitle
                : l.photosSubtitleViewOnly,
            onTap: () => _open(
              context,
              PhotosScreen(auth: auth, imageSource: imageSource),
            ),
          ),


          if (role.canEditProfile) ...[
            // Above the hours on purpose: a venue is defined by its rooms
            // before it is defined by when they are open.
            _Entry(
              tile: asTiles,
              icon: Icons.table_restaurant_outlined,
              title: l.tablesAndRooms,
              subtitle: l.tablesAndRoomsSubtitle,
              onTap: () => _open(context, SpacesScreen(auth: auth)),
            ),
            _Entry(
              tile: asTiles,
              icon: Icons.schedule,
              title: l.openingHours,
              subtitle: l.openingHoursSubtitle,
              onTap: () => _open(context, HoursScreen(auth: auth)),
            ),
            _Entry(
              tile: asTiles,
              icon: Icons.storefront,
              title: l.venueDetails,
              subtitle: l.venueDetailsSubtitle,
              onTap: () => _open(context, ProfileScreen(auth: auth)),
            ),
            _Entry(
              tile: asTiles,
              icon: Icons.palette_outlined,
              title: l.branding,
              subtitle: l.brandingSubtitle,
              onTap: () => _open(context, BrandingScreen(auth: auth)),
            ),
          ],

          if (role.canManageStaff)
            _Entry(
              tile: asTiles,
              icon: Icons.people_outline,
              title: l.whoHasAccess,
              subtitle: l.whoHasAccessSubtitle,
              onTap: () => _open(context, StaffScreen(auth: auth)),
            ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l.navManage),
        actions: [
          if (auth.hasMultipleVenues)
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              tooltip: l.switchVenue,
              onPressed: auth.changeVenue,
            ),
        ],
      ),
      body: ListView(
        // The last rows sat under the navigation bar without this: the list
        // grew past the fold when the language control was added, and a
        // control half-hidden behind the bar cannot be tapped at all.
        padding: contentInsets(context).copyWith(bottom: 32),
        children: [
          if (venue != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(venue.name, style: theme.textTheme.titleLarge),
                  Text(
                    l.youAreRoleHere(
                      venue.city,
                      venue.role.label(l),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(),

          if (asTiles)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.7,
                children: entries,
              ),
            )
          else
            ...entries,

          if (!role.canEditProfile)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l.managedByOwnerOrManager,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),

          const Divider(),
          // The language control lives here rather than behind venue details:
          // someone who cannot read the app has to be able to find it, and
          // Manage is the only screen reachable without reading a sentence.
          LanguageToggle(controller: localeController),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text(
              l.signOut,
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
    this.tile = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Laid out as a card in a grid rather than as a row in a list.
  final bool tile;

  @override
  Widget build(BuildContext context) {
    if (!tile) {
      return ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );
    }

    // A card rather than a row, once there is width for a grid. Six entries
    // down the left edge of a 2560px screen is a list pretending the rest of
    // the screen is not there.
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 20),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 2),
            // Flexible, so a long subtitle drops a line rather than pushing
            // the tile past the cell the grid gave it. A fixed two lines
            // overflowed by 28 pixels the moment the text scale went up.
            Flexible(
              child: Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
