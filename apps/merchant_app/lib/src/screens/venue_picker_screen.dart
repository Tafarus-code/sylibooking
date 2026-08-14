import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';
import '../auth_controller.dart';
import '../labels.dart';
import 'create_venue_screen.dart';

/// Which venue am I working tonight?
///
/// Only ever shown to accounts with more than one venue — someone who runs a
/// single place should never meet a chooser with one item in it.
class VenuePickerScreen extends StatelessWidget {
  const VenuePickerScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = L.of(context);
    final canGoBack = auth.selectedVenue != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.chooseAVenue),
        automaticallyImplyLeading: false,
        actions: [
          if (!canGoBack)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: l.signOut,
              onPressed: auth.signOut,
            ),
        ],
        leading: canGoBack
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: l.keepCurrentVenue,
                onPressed: () => auth.selectVenue(auth.selectedVenue!),
              )
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CreateVenueScreen(auth: auth)),
        ),
        icon: const Icon(Icons.add_business_outlined),
        label: Text(l.newVenue),
      ),
      body: ListView(
        padding: contentInsets(context, vertical: 8).copyWith(bottom: 88),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              l.everythingAppliesToVenue,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final venue in auth.venues)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  child: Icon(
                    venue.type == 'lounge'
                        ? Icons.local_fire_department
                        : Icons.restaurant,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                title: Text(venue.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(venue.city),
                    Text(
                      venue.role.name(l),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                trailing: venue.id == auth.selectedVenueId
                    ? Icon(Icons.check, color: theme.colorScheme.primary)
                    : const Icon(Icons.chevron_right),
                onTap: () => auth.selectVenue(venue),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown when an account has a login but no venue attached to it yet.
class NoVenueScreen extends StatelessWidget {
  const NoVenueScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = L.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l.signOut,
            onPressed: auth.signOut,
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.store_mall_directory_outlined,
                size: 56,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(l.noVenueYet, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                l.noVenueYetDetail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CreateVenueScreen(auth: auth),
                  ),
                ),
                icon: const Icon(Icons.add_business_outlined),
                label: Text(l.createVenue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
