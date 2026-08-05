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
import 'reviews_screen.dart';
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

          // Staff can reach the menu: marking a dish sold out is theirs to do.
          _Entry(
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

          // Everyone may read them. A merchant who cannot see their
          // reviews here reads them on Facebook instead.
          _Entry(
            icon: Icons.reviews_outlined,
            title: l.reviews,
            subtitle: l.reviewsSubtitle,
            onTap: () => _open(context, ReviewsScreen(auth: auth)),
          ),

          if (role.canEditProfile) ...[
            // Above the hours on purpose: a venue is defined by its rooms
            // before it is defined by when they are open.
            _Entry(
              icon: Icons.table_restaurant_outlined,
              title: l.tablesAndRooms,
              subtitle: l.tablesAndRoomsSubtitle,
              onTap: () => _open(context, SpacesScreen(auth: auth)),
            ),
            _Entry(
              icon: Icons.schedule,
              title: l.openingHours,
              subtitle: l.openingHoursSubtitle,
              onTap: () => _open(context, HoursScreen(auth: auth)),
            ),
            _Entry(
              icon: Icons.storefront,
              title: l.venueDetails,
              subtitle: l.venueDetailsSubtitle,
              onTap: () => _open(context, ProfileScreen(auth: auth)),
            ),
            _Entry(
              icon: Icons.palette_outlined,
              title: l.branding,
              subtitle: l.brandingSubtitle,
              onTap: () => _open(context, BrandingScreen(auth: auth)),
            ),
          ],

          if (role.canManageStaff)
            _Entry(
              icon: Icons.people_outline,
              title: l.whoHasAccess,
              subtitle: l.whoHasAccessSubtitle,
              onTap: () => _open(context, StaffScreen(auth: auth)),
            ),

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
