"""What becomes of a deposit once the booking it was taken for has ended.

D1: taken off the bill when the guests arrive, kept when they do not. Before
this the 50,000 GNF was charged and then nothing happened to it, which is the
entire commercial point of taking one.

The property under the most scrutiny here is that a forfeiture is decided by
the grace period the booking was *sold* under. That is enforced upstream — the
booking only reaches `no_show` by way of its own captured window — but a
customer disputing a forfeiture is disputing this exact chain, so it is
tested end to end rather than assumed from the parts.
"""

from datetime import timedelta
from decimal import Decimal

from django.contrib.auth.models import User
from django.core.management import call_command
from django.test import override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from establishments.models import Establishment, MerchantMembership, Space
from payments.models import Payment
from payments.services import refund_deposit, settle_deposit
from reservations.availability import is_space_available
from reservations.models import Reservation


class DepositTestBase(APITestCase):
    def setUp(self):
        self.restaurant = Establishment.objects.create(
            name='Chez Fatou',
            type=Establishment.Type.RESTAURANT,
            city='Conakry',
            address='Kaloum',
        )
        self.lounge = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum',
        )
        self.table = Space.objects.create(
            establishment=self.restaurant, name='Table 1', capacity=4
        )
        self.salon = Space.objects.create(
            establishment=self.lounge, name='Salon 1', capacity=6
        )
        self.owner = User.objects.create_user('amadou', password='pw-for-tests')
        for venue in (self.restaurant, self.lounge):
            MerchantMembership.objects.create(
                user=self.owner,
                establishment=venue,
                role=MerchantMembership.Role.OWNER,
            )

    def authenticate(self):
        token, _ = Token.objects.get_or_create(user=self.owner)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

    def booking_with_deposit(
        self,
        space=None,
        when=None,
        status_=Reservation.Status.CONFIRMED,
        payment_status=Payment.Status.COMPLETED,
        amount='50000.00',
        **kwargs,
    ):
        reservation = Reservation.objects.create(
            space=space or self.table,
            customer_name='Mariama',
            customer_phone='+224620000000',
            datetime=when or (timezone.now() - timedelta(minutes=45)),
            party_size=2,
            status=status_,
            **kwargs,
        )
        Payment.objects.create(
            reservation=reservation,
            provider=Payment.Provider.ORANGE_MONEY,
            amount=Decimal(amount),
            status=payment_status,
            provider_reference='MOCK-DEPOSIT-1',
        )
        return reservation

    def cash_booking(self, when=None):
        return Reservation.objects.create(
            space=self.table,
            customer_name='Ibrahima',
            customer_phone='+224620000001',
            datetime=when or (timezone.now() - timedelta(minutes=45)),
            party_size=2,
            status=Reservation.Status.CONFIRMED,
        )


class SettlementTests(DepositTestBase):
    def test_arriving_takes_the_deposit_off_the_bill(self):
        reservation = self.booking_with_deposit()
        reservation.status = Reservation.Status.COMPLETED
        reservation.save(update_fields=['status'])

        payment = settle_deposit(reservation)

        self.assertEqual(payment.outcome, Payment.Outcome.OFFSET)

    def test_not_arriving_keeps_it(self):
        reservation = self.booking_with_deposit()
        reservation.status = Reservation.Status.NO_SHOW
        reservation.save(update_fields=['status'])

        payment = settle_deposit(reservation)

        self.assertEqual(payment.outcome, Payment.Outcome.FORFEITED)

    def test_a_cash_booking_has_nothing_to_settle(self):
        reservation = self.cash_booking()
        reservation.status = Reservation.Status.COMPLETED
        reservation.save(update_fields=['status'])

        self.assertIsNone(settle_deposit(reservation))

    def test_a_payment_that_never_completed_is_not_settled(self):
        """Nothing was taken, so there is nothing to keep or give back."""
        reservation = self.booking_with_deposit(
            payment_status=Payment.Status.FAILED
        )
        reservation.status = Reservation.Status.NO_SHOW
        reservation.save(update_fields=['status'])

        self.assertIsNone(settle_deposit(reservation))

    def test_an_open_booking_is_left_alone(self):
        reservation = self.booking_with_deposit()

        payment = settle_deposit(reservation)

        self.assertEqual(payment.outcome, Payment.Outcome.NONE)

    def test_a_cancelled_booking_is_left_alone(self):
        """Cancellation has its own rules, and they are not this slice's."""
        reservation = self.booking_with_deposit(
            status_=Reservation.Status.CANCELLED
        )

        payment = settle_deposit(reservation)

        self.assertEqual(payment.outcome, Payment.Outcome.NONE)

    def test_settling_twice_does_not_forfeit_twice(self):
        """The sweep runs constantly once it is on a scheduler."""
        reservation = self.booking_with_deposit()
        reservation.status = Reservation.Status.NO_SHOW
        reservation.save(update_fields=['status'])
        settle_deposit(reservation)

        settle_deposit(reservation)

        outcomes = list(
            Payment.objects.filter(reservation=reservation).values_list(
                'outcome', flat=True
            )
        )
        self.assertEqual(outcomes, [Payment.Outcome.FORFEITED])

    def test_an_outcome_is_not_rewritten_by_a_later_status_change(self):
        """Once settled, settled. Reopening the question invites disputes."""
        reservation = self.booking_with_deposit()
        reservation.status = Reservation.Status.NO_SHOW
        reservation.save(update_fields=['status'])
        settle_deposit(reservation)

        reservation.status = Reservation.Status.COMPLETED
        reservation.save(update_fields=['status'])
        payment = settle_deposit(reservation)

        self.assertEqual(payment.outcome, Payment.Outcome.FORFEITED)

    def test_the_payment_itself_stays_completed(self):
        """Outcome is a separate axis: the money did arrive either way."""
        reservation = self.booking_with_deposit()
        reservation.status = Reservation.Status.NO_SHOW
        reservation.save(update_fields=['status'])

        payment = settle_deposit(reservation)

        self.assertEqual(payment.status, Payment.Status.COMPLETED)


class SettlementThroughTheFlowTests(DepositTestBase):
    def test_marking_arrived_settles_the_deposit(self):
        reservation = self.booking_with_deposit()
        self.authenticate()

        response = self.client.post(
            reverse('reservation-complete', args=[reservation.pk])
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(
            response.data['payment']['outcome'], Payment.Outcome.OFFSET
        )

    def test_the_lapse_sweep_forfeits_the_deposit(self):
        # 45 minutes past, at a restaurant holding tables for 30.
        reservation = self.booking_with_deposit()

        call_command('lapse_no_shows', verbosity=0)

        reservation.refresh_from_db()
        self.assertEqual(reservation.status, Reservation.Status.NO_SHOW)
        self.assertEqual(
            reservation.payments.first().outcome, Payment.Outcome.FORFEITED
        )

    def test_the_same_delay_at_a_lounge_forfeits_nothing(self):
        """The per-type window, followed all the way to the money."""
        reservation = self.booking_with_deposit(space=self.salon)

        call_command('lapse_no_shows', verbosity=0)

        reservation.refresh_from_db()
        self.assertEqual(reservation.status, Reservation.Status.CONFIRMED)
        self.assertEqual(
            reservation.payments.first().outcome, Payment.Outcome.NONE
        )

    @override_settings(NO_SHOW_WINDOW_MINUTES={'restaurant': 5, 'lounge': 5})
    def test_a_deposit_is_kept_under_the_terms_it_was_sold_under(self):
        """**The dispute this design exists to prevent, end to end.**

        Booked at a lounge holding tables for ninety minutes. The venue then
        cuts its window to five. Forty-five minutes after the booking time the
        sweep runs — and must not keep this customer's money, because they
        were sold ninety.
        """
        reservation = self.booking_with_deposit(
            space=self.salon,
            when=timezone.now() - timedelta(minutes=45),
            no_show_after_minutes=90,
        )

        call_command('lapse_no_shows', verbosity=0)

        reservation.refresh_from_db()
        self.assertEqual(reservation.status, Reservation.Status.CONFIRMED)
        self.assertEqual(
            reservation.payments.first().outcome,
            Payment.Outcome.NONE,
            'a deposit was kept under a window the customer never agreed to',
        )

    @override_settings(NO_SHOW_WINDOW_MINUTES={'restaurant': 240, 'lounge': 240})
    def test_and_is_kept_when_that_window_really_has_passed(self):
        """The other half: lengthening the venue's window afterwards does not
        rescue a booking that already lapsed under a shorter one."""
        reservation = self.booking_with_deposit(
            when=timezone.now() - timedelta(minutes=45),
            no_show_after_minutes=30,
        )

        call_command('lapse_no_shows', verbosity=0)

        reservation.refresh_from_db()
        self.assertEqual(reservation.status, Reservation.Status.NO_SHOW)
        self.assertEqual(
            reservation.payments.first().outcome, Payment.Outcome.FORFEITED
        )


class RefundTests(DepositTestBase):
    def test_a_refund_goes_through_the_provider_and_is_recorded(self):
        reservation = self.booking_with_deposit()
        payment = reservation.payments.first()

        refund_deposit(payment)

        payment.refresh_from_db()
        self.assertEqual(payment.outcome, Payment.Outcome.REFUNDED)

    def test_refunding_twice_is_a_no_op(self):
        reservation = self.booking_with_deposit()
        payment = reservation.payments.first()
        refund_deposit(payment)

        refund_deposit(payment)

        payment.refresh_from_db()
        self.assertEqual(payment.outcome, Payment.Outcome.REFUNDED)

    def test_every_provider_must_offer_one(self):
        """Abstract on the interface, so the real adapter is an adapter."""
        from payments.providers import PaymentProvider

        self.assertIn('refund', PaymentProvider.__abstractmethods__)


class DashboardTests(DepositTestBase):
    def dashboard(self):
        self.authenticate()
        today = timezone.now().date()
        return self.client.get(
            reverse('payment-dashboard'),
            {
                'establishment': self.restaurant.pk,
                'from': (today - timedelta(days=7)).isoformat(),
                'to': today.isoformat(),
            },
        )

    def test_a_kept_deposit_is_reported_separately(self):
        reservation = self.booking_with_deposit()
        reservation.status = Reservation.Status.NO_SHOW
        reservation.save(update_fields=['status'])
        settle_deposit(reservation)

        response = self.dashboard()

        self.assertEqual(
            Decimal(response.data['payments']['forfeited']),
            Decimal('50000.00'),
        )
        self.assertEqual(response.data['payments']['forfeited_count'], 1)

    def test_a_deposit_taken_off_the_bill_is_reported_separately(self):
        reservation = self.booking_with_deposit()
        reservation.status = Reservation.Status.COMPLETED
        reservation.save(update_fields=['status'])
        settle_deposit(reservation)

        response = self.dashboard()

        self.assertEqual(
            Decimal(response.data['payments']['offset']),
            Decimal('50000.00'),
        )
        self.assertEqual(
            Decimal(response.data['payments']['forfeited']),
            Decimal('0.00'),
        )

    def test_collected_still_counts_every_payment_that_arrived(self):
        """Splitting it would understate what the venue actually took.

        A deposit taken off the bill still arrived; it was handed back as a
        discount at the counter, which this platform never sees.
        """
        arrived = self.booking_with_deposit(
            when=timezone.now() - timedelta(minutes=45)
        )
        arrived.status = Reservation.Status.COMPLETED
        arrived.save(update_fields=['status'])
        settle_deposit(arrived)

        missed = self.booking_with_deposit(
            when=timezone.now() - timedelta(minutes=200)
        )
        missed.status = Reservation.Status.NO_SHOW
        missed.save(update_fields=['status'])
        settle_deposit(missed)

        response = self.dashboard()

        self.assertEqual(
            Decimal(response.data['payments']['collected']),
            Decimal('100000.00'),
        )
        self.assertEqual(
            Decimal(response.data['payments']['offset']),
            Decimal('50000.00'),
        )
        self.assertEqual(
            Decimal(response.data['payments']['forfeited']),
            Decimal('50000.00'),
        )

    def test_an_unsettled_deposit_counts_as_neither(self):
        self.booking_with_deposit()

        response = self.dashboard()

        self.assertEqual(
            Decimal(response.data['payments']['collected']),
            Decimal('50000.00'),
        )
        self.assertEqual(
            Decimal(response.data['payments']['offset']),
            Decimal('0.00'),
        )
        self.assertEqual(
            Decimal(response.data['payments']['forfeited']),
            Decimal('0.00'),
        )


class RefundWithoutReversingTests(DepositTestBase):
    """Giving a kept deposit back without pretending the no-show did not happen.

    A customer who turns up three quarters of an hour late has still missed
    their table: the venue held it and then lost it. But a merchant who seats
    them anyway, or simply judges the charge harsh, needs a way to return the
    money that does not require rewriting the record.
    """

    def missed_with_kept_deposit(self):
        reservation = self.booking_with_deposit()
        reservation.status = Reservation.Status.NO_SHOW
        reservation.save(update_fields=['status'])
        settle_deposit(reservation)
        return reservation

    def refund_url(self, reservation):
        return reverse('reservation-refund-deposit', args=[reservation.pk])

    def test_an_owner_can_give_a_kept_deposit_back(self):
        reservation = self.missed_with_kept_deposit()
        self.authenticate()

        response = self.client.post(self.refund_url(reservation))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(
            reservation.payments.first().outcome, Payment.Outcome.REFUNDED
        )

    def test_the_booking_is_still_missed_afterwards(self):
        """**The point of this endpoint.**

        The money goes back; the record does not change. A venue that held a
        table and lost it should still see that in its own figures.
        """
        reservation = self.missed_with_kept_deposit()
        self.authenticate()

        self.client.post(self.refund_url(reservation))

        reservation.refresh_from_db()
        self.assertEqual(reservation.status, Reservation.Status.NO_SHOW)
        self.assertIsNone(reservation.arrived_at)

    def test_the_slot_stays_released(self):
        """A missed booking freed its table; refunding must not take it back."""
        reservation = self.missed_with_kept_deposit()
        self.authenticate()

        self.client.post(self.refund_url(reservation))

        self.assertTrue(is_space_available(self.table, reservation.datetime))

    def test_a_manager_can_too(self):
        reservation = self.missed_with_kept_deposit()
        manager = User.objects.create_user('ibrahima', password='pw-for-tests')
        MerchantMembership.objects.create(
            user=manager,
            establishment=self.restaurant,
            role=MerchantMembership.Role.MANAGER,
        )
        token, _ = Token.objects.get_or_create(user=manager)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

        response = self.client.post(self.refund_url(reservation))

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_staff_cannot(self):
        """Handing a customer their deposit back is a decision about the
        venue's takings, not a floor call."""
        reservation = self.missed_with_kept_deposit()
        floor = User.objects.create_user('aissatou', password='pw-for-tests')
        MerchantMembership.objects.create(
            user=floor,
            establishment=self.restaurant,
            role=MerchantMembership.Role.STAFF,
        )
        token, _ = Token.objects.get_or_create(user=floor)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

        response = self.client.post(self.refund_url(reservation))

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(
            reservation.payments.first().outcome, Payment.Outcome.FORFEITED
        )

    def test_a_signed_out_caller_cannot(self):
        reservation = self.missed_with_kept_deposit()

        response = self.client.post(self.refund_url(reservation))

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_a_deposit_taken_off_a_bill_cannot_be_refunded_here(self):
        """That money already went back, as a discount at the till."""
        reservation = self.booking_with_deposit()
        reservation.status = Reservation.Status.COMPLETED
        reservation.save(update_fields=['status'])
        settle_deposit(reservation)
        self.authenticate()

        response = self.client.post(self.refund_url(reservation))

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)
        self.assertEqual(
            reservation.payments.first().outcome, Payment.Outcome.OFFSET
        )

    def test_an_unsettled_deposit_cannot_be_refunded_here(self):
        """Nothing has been kept yet, so there is nothing to give back."""
        reservation = self.booking_with_deposit()
        self.authenticate()

        response = self.client.post(self.refund_url(reservation))

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)

    def test_a_cash_booking_has_nothing_to_refund(self):
        reservation = self.cash_booking()
        reservation.status = Reservation.Status.NO_SHOW
        reservation.save(update_fields=['status'])
        self.authenticate()

        response = self.client.post(self.refund_url(reservation))

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)

    def test_refunding_twice_is_refused_the_second_time(self):
        reservation = self.missed_with_kept_deposit()
        self.authenticate()
        self.client.post(self.refund_url(reservation))

        response = self.client.post(self.refund_url(reservation))

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)

    @override_settings(
        PAYMENT_PROVIDERS={
            'orange_money': 'payments.tests.UnreachablePaymentProvider'
        }
    )
    def test_an_unreachable_provider_does_not_claim_the_money_went_back(self):
        """We do not know whether it took it, so we must not say it did."""
        reservation = self.missed_with_kept_deposit()
        self.authenticate()

        response = self.client.post(self.refund_url(reservation))

        self.assertEqual(response.status_code, status.HTTP_502_BAD_GATEWAY)
        self.assertEqual(
            reservation.payments.first().outcome, Payment.Outcome.FORFEITED
        )

    def test_the_takings_stop_counting_it_as_kept(self):
        reservation = self.missed_with_kept_deposit()
        self.authenticate()
        self.client.post(self.refund_url(reservation))

        today = timezone.now().date()
        response = self.client.get(
            reverse('payment-dashboard'),
            {
                'establishment': self.restaurant.pk,
                'from': (today - timedelta(days=7)).isoformat(),
                'to': today.isoformat(),
            },
        )

        payments = response.data['payments']
        self.assertEqual(Decimal(payments['forfeited']), Decimal('0.00'))
        self.assertEqual(payments['forfeited_count'], 0)
        # Accounted for rather than simply gone from the figure it was in.
        self.assertEqual(Decimal(payments['refunded']), Decimal('50000.00'))
