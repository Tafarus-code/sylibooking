"""Customer identity: how to reach someone, and how they get back in.

Split from the account itself because reaching a customer is a different
concern from authenticating them, and because a phone number is the one piece
of contact detail that matters in this market — email is the fallback, not the
other way round.
"""

import hashlib
import secrets
from datetime import timedelta

from django.conf import settings
from django.db import models
from django.utils import timezone


class CustomerProfile(models.Model):
    """Where to reach a customer who has an account.

    Both fields are optional, and an account can exist with neither — the app
    never demanded contact details and still does not. But a reset needs
    somewhere to send a code, so the app asks for one at signup and says why.
    """

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='customer_profile',
    )
    phone = models.CharField(
        max_length=30,
        blank=True,
        db_index=True,
        help_text='For an SMS code. The usual way back in here.',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        contact = self.phone or self.user.email or 'no contact'
        return f'{self.user.username} ({contact})'

    @property
    def has_contact(self):
        return bool(self.phone or self.user.email)


class PasswordResetCode(models.Model):
    """A short code, sent once, good for a few minutes.

    A code rather than a link: a link in an SMS is a phishing lesson nobody
    asked for, and typing six digits into the app the customer already has
    open is fewer steps than opening a browser.

    The code itself is never stored — only its hash, for the same reason
    passwords are hashed. A leak of this table must not hand anybody a way
    into an account.
    """

    class Channel(models.TextChoices):
        SMS = 'sms', 'SMS'
        EMAIL = 'email', 'Email'

    #: Long enough not to be guessed inside the window, short enough to retype.
    CODE_LENGTH = 6

    #: A code is worth using for this long and no longer.
    LIFETIME = timedelta(minutes=15)

    #: Wrong guesses before the code is burned, so the window cannot be
    #: brute-forced by a script.
    MAX_ATTEMPTS = 5

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='password_reset_codes',
    )
    code_hash = models.CharField(max_length=64, db_index=True)
    channel = models.CharField(max_length=10, choices=Channel.choices)
    destination = models.CharField(
        max_length=200,
        help_text='Where it was sent, masked when shown back to the customer.',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    used_at = models.DateTimeField(null=True, blank=True)
    attempts = models.PositiveSmallIntegerField(default=0)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f'reset for {self.user.username} via {self.channel}'

    @classmethod
    def hash_code(cls, code):
        return hashlib.sha256(code.encode()).hexdigest()

    @classmethod
    def issue(cls, user, channel, destination):
        """Make a new code, invalidating any still outstanding.

        Asking for a second code has to make the first useless, or a code read
        over someone's shoulder stays good for a quarter of an hour after the
        customer has already asked for another.
        """
        cls.objects.filter(user=user, used_at__isnull=True).update(
            used_at=timezone.now()
        )

        code = ''.join(
            secrets.choice('0123456789') for _ in range(cls.CODE_LENGTH)
        )
        record = cls.objects.create(
            user=user,
            code_hash=cls.hash_code(code),
            channel=channel,
            destination=destination,
            expires_at=timezone.now() + cls.LIFETIME,
        )
        # Returned, never stored: this is the only moment the plain code
        # exists, and it goes straight to the notifier.
        return record, code

    @property
    def is_usable(self):
        return (
            self.used_at is None
            and self.attempts < self.MAX_ATTEMPTS
            and timezone.now() < self.expires_at
        )

    def matches(self, code):
        """Check a code, counting the attempt whether or not it was right."""
        self.attempts += 1
        self.save(update_fields=['attempts'])
        return secrets.compare_digest(self.code_hash, self.hash_code(code))

    def consume(self):
        self.used_at = timezone.now()
        self.save(update_fields=['used_at'])
