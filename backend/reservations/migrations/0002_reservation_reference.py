"""Give every reservation an unguessable reference.

Written by hand rather than generated: a plain AddField with a callable default
evaluates it once and writes the *same* UUID to every existing row, which then
fails the unique constraint. So the column arrives nullable, gets filled in
row by row, and only then becomes unique and non-null.
"""

import uuid

from django.db import migrations, models


def populate_references(apps, schema_editor):
    Reservation = apps.get_model('reservations', 'Reservation')
    for reservation in Reservation.objects.filter(reference__isnull=True):
        reservation.reference = uuid.uuid4()
        reservation.save(update_fields=['reference'])


def clear_references(apps, schema_editor):
    """Reverse is a no-op: the column itself is dropped by the AddField."""


class Migration(migrations.Migration):
    dependencies = [
        ('reservations', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='reservation',
            name='reference',
            field=models.UUIDField(null=True, editable=False),
        ),
        migrations.RunPython(populate_references, clear_references),
        migrations.AlterField(
            model_name='reservation',
            name='reference',
            field=models.UUIDField(
                db_index=True,
                default=uuid.uuid4,
                editable=False,
                help_text=(
                    'Unguessable handle the customer uses to view or cancel '
                    'their own booking. Customers have no accounts, so this is '
                    'what proves the booking is theirs — the sequential id '
                    'must not be used for that.'
                ),
                unique=True,
            ),
        ),
    ]
