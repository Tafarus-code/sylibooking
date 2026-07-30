import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../auth_controller.dart';

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
    final canGoBack = auth.selectedVenue != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a venue'),
        automaticallyImplyLeading: false,
        actions: [
          if (!canGoBack)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign out',
              onPressed: auth.signOut,
            ),
        ],
        leading: canGoBack
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Keep current venue',
                onPressed: () => auth.selectVenue(auth.selectedVenue!),
              )
            : null,
      ),
      body: ListView(
        padding: contentInsets(context, vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              'Everything you do next applies to the venue you pick.',
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
                      venue.roleDisplay,
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sylibooking Merchant'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
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
              Text('No venue yet', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'This account is not a member of any establishment. An owner '
                'can add you to theirs, or an admin can set one up.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
