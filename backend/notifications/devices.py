"""Where a merchant's phone can be reached, so an alert arrives unopened.

Slice 7 already records what would be sent. This is the missing half: a push
token, so the tablet on the counter buzzes when a booking lands rather than
waiting for somebody to pull down to refresh.

Deliberately per-device rather than per-user. A venue often has a tablet at
the counter and the owner's phone in their pocket, and an alert that reaches
only whichever signed in most recently is worse than no alert — the person
holding the other device believes they are covered.
"""

from django.conf import settings
from django.db import models


class DeviceToken(models.Model):
    """One installation of one app, belonging to one account."""

    class Platform(models.TextChoices):
        ANDROID = 'android', 'Android'
        IOS = 'ios', 'iOS'
        WEB = 'web', 'Web'

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='device_tokens',
    )
    # Firebase reissues these: on reinstall, on restore to a new handset, and
    # occasionally for its own reasons. Unique so a token that moves between
    # accounts — a shared tablet re-signed-in — belongs to one of them rather
    # than to both.
    token = models.CharField(max_length=255, unique=True)
    platform = models.CharField(
        max_length=16,
        choices=Platform.choices,
        default=Platform.ANDROID,
    )
    created_at = models.DateTimeField(auto_now_add=True)
    # Touched on every registration, which the app does at each launch. A
    # token nobody has confirmed for months is a phone that was wiped, and
    # sending to it is how a push quota is wasted.
    last_seen_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-last_seen_at']

    def __str__(self):
        return f'{self.user} on {self.get_platform_display()}'
