"""Give the staff relationship a role, via a through model.

The ordering here matters. Altering `staff` to use a through model drops the
auto-created join table, so the existing rows are copied into
MerchantMembership *first*. Doing it the other way round silently revokes
every merchant's access.

Existing rows become owners: the old join table recorded who had access but
never in what capacity, and at the time of writing no establishment had more
than one staff user, so there are no employee-distinct accounts to mislabel.
"""

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


def copy_staff_into_memberships(apps, schema_editor):
    """Old join table -> MerchantMembership, everyone an owner."""
    Establishment = apps.get_model('establishments', 'Establishment')
    MerchantMembership = apps.get_model('establishments', 'MerchantMembership')

    # `staff` is still the plain M2M at this point in the migration state, so
    # its auto-created through model is where the existing rows live.
    OldJoin = Establishment.staff.through

    MerchantMembership.objects.bulk_create(
        [
            MerchantMembership(
                user_id=row.user_id,
                establishment_id=row.establishment_id,
                role='owner',
            )
            for row in OldJoin.objects.all()
        ]
    )


def copy_memberships_back(apps, schema_editor):
    """Reverse: memberships -> the restored join table, losing the roles."""
    Establishment = apps.get_model('establishments', 'Establishment')
    MerchantMembership = apps.get_model('establishments', 'MerchantMembership')
    OldJoin = Establishment.staff.through

    OldJoin.objects.bulk_create(
        [
            OldJoin(
                user_id=membership.user_id,
                establishment_id=membership.establishment_id,
            )
            for membership in MerchantMembership.objects.all()
        ]
    )


class Migration(migrations.Migration):
    dependencies = [
        ('establishments', '0005_alter_photo_options_alter_review_options'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AddField(
            model_name='establishment',
            name='description',
            field=models.TextField(
                blank=True,
                help_text='Longer blurb shown on the customer detail screen.',
            ),
        ),
        migrations.AddField(
            model_name='establishment',
            name='tagline',
            field=models.CharField(
                blank=True,
                help_text='One line, e.g. "Rooftop chicha over Kaloum".',
                max_length=200,
            ),
        ),
        migrations.CreateModel(
            name='MerchantMembership',
            fields=[
                (
                    'id',
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name='ID',
                    ),
                ),
                (
                    'role',
                    models.CharField(
                        choices=[
                            ('owner', 'Owner'),
                            ('manager', 'Manager'),
                            ('staff', 'Staff'),
                        ],
                        default='staff',
                        help_text=(
                            'Owner: everything, including managing who else '
                            'has access. Manager: the venue and its profile, '
                            'but not the staff list. Staff: day-to-day floor '
                            'work, plus toggling menu availability.'
                        ),
                        max_length=20,
                    ),
                ),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                (
                    'establishment',
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name='memberships',
                        to='establishments.establishment',
                    ),
                ),
                (
                    'user',
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name='merchant_memberships',
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={'ordering': ['establishment', 'role', 'user']},
        ),
        # Before the field is removed below, which drops the old join table.
        migrations.RunPython(
            copy_staff_into_memberships, copy_memberships_back
        ),
        # Django refuses to add `through=` with AlterField, so the field is
        # dropped and re-added. Safe only because the rows were copied above.
        migrations.RemoveField(model_name='establishment', name='staff'),
        migrations.AddField(
            model_name='establishment',
            name='staff',
            field=models.ManyToManyField(
                blank=True,
                help_text=(
                    'Users who may see and manage this establishment in the '
                    'merchant app. What each may actually do is decided by '
                    'their membership role, not by this field.'
                ),
                related_name='establishments',
                through='establishments.MerchantMembership',
                to=settings.AUTH_USER_MODEL,
            ),
        ),
        migrations.AddConstraint(
            model_name='merchantmembership',
            constraint=models.UniqueConstraint(
                fields=('user', 'establishment'),
                name='unique_membership_per_user_per_establishment',
            ),
        ),
    ]
