"""Venues a customer has saved.

Kept in its own module rather than in models.py because it belongs to the
customer half of the product, which the establishments app otherwise knows
nothing about.
"""

from django.conf import settings
from django.db import models

from .models import Establishment


class Favourite(models.Model):
    """One customer, one venue, saved for later.

    Only signed-in customers have rows here. Someone who never makes an
    account keeps their list on their phone instead — the whole point of
    optional accounts is that the app works without one, and saving a venue is
    exactly the sort of small act that must not demand a signup.
    """

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='favourites',
    )
    establishment = models.ForeignKey(
        Establishment,
        on_delete=models.CASCADE,
        related_name='favourited_by',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        constraints = [
            # Tapping the heart twice is one favourite, not two.
            models.UniqueConstraint(
                fields=['user', 'establishment'],
                name='one_favourite_per_venue_per_customer',
            ),
        ]

    def __str__(self):
        return f'{self.user} ♥ {self.establishment}'
