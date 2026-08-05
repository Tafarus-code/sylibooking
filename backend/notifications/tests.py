"""The task queue itself, before anything important rides on it.

Deliberately narrow. These do not test that a reminder is correct — nothing
sends reminders yet — they test that work queued from a request reaches a
worker, that a task which fails gives up rather than retrying for ever, and
that a broker nobody can reach does not take a customer's booking down with
it. Those are the three ways a queue breaks a product that was working before
it existed.
"""

from unittest import mock

from celery.exceptions import Retry
from config import celery_app
from django.test import SimpleTestCase, override_settings

from notifications.tasks import send_test_notification


class WiringTests(SimpleTestCase):
    def test_the_app_reads_djangos_settings(self):
        """One place a deployment is configured, not two.

        Compared against the setting rather than a literal: the point is that
        `config_from_object` is working, and hardcoding the default would
        make this fail in CI, where the broker is a service on another host.
        """
        from django.conf import settings

        self.assertEqual(
            celery_app.conf.broker_url, settings.CELERY_BROKER_URL
        )
        self.assertTrue(celery_app.conf.broker_url.startswith('redis://'))

    def test_the_task_is_discovered(self):
        """Autodiscovery is lazy, so this forces it the way a worker does."""
        celery_app.loader.import_default_modules()

        self.assertIn(
            'notifications.tasks.send_test_notification', celery_app.tasks
        )

    def test_a_lost_worker_does_not_lose_the_work(self):
        """acks_late: a task is acknowledged when it finishes, not when it
        starts. Repeating a reminder beats dropping one."""
        self.assertTrue(celery_app.conf.task_acks_late)

    def test_a_task_cannot_run_for_ever(self):
        """A worker slot held indefinitely is a queue that silently stops."""
        self.assertIsNotNone(celery_app.conf.task_time_limit)
        self.assertLess(
            celery_app.conf.task_soft_time_limit,
            celery_app.conf.task_time_limit,
        )

    def test_eager_mode_does_not_swallow_failures(self):
        """Without this a broken task passes its own test."""
        self.assertTrue(celery_app.conf.task_eager_propagates)


@override_settings(CELERY_TASK_ALWAYS_EAGER=True)
class EagerExecutionTests(SimpleTestCase):
    def test_a_task_runs_in_process_under_test(self):
        result = send_test_notification.delay('hello')

        self.assertTrue(result.successful())
        self.assertEqual(result.get(), 'hello')

    def test_calling_it_directly_works_too(self):
        """Tasks are ordinary functions; the decorator is not the behaviour."""
        self.assertEqual(send_test_notification('direct'), 'direct')


class RetryTests(SimpleTestCase):
    def test_a_failing_task_retries_a_bounded_number_of_times(self):
        """Retrying for ever is how a queue fills up and stops moving."""
        self.assertEqual(send_test_notification.max_retries, 3)
        self.assertTrue(send_test_notification.retry_backoff)

    def test_a_failure_is_retried_rather_than_swallowed(self):
        """A task that hides its own failure is worse than no task: the
        reminder never arrives and nothing records that it did not."""
        with mock.patch(
            'notifications.tasks.logger.info', side_effect=RuntimeError('boom')
        ):
            with self.assertRaises((Retry, RuntimeError)):
                send_test_notification.apply(throw=True).get()


class UnreachableBrokerTests(SimpleTestCase):
    """The failure mode that matters most.

    A queue is an addition to a product that already worked. If Redis being
    down means a customer cannot book a table, the queue has made things
    worse — so the caller has to be able to decide that for itself rather
    than discovering it as a 500.
    """

    @override_settings(
        CELERY_TASK_ALWAYS_EAGER=False,
        CELERY_BROKER_URL='redis://127.0.0.1:6999/0',
    )
    def test_queueing_against_a_dead_broker_raises_rather_than_hanging(self):
        with mock.patch.object(
            celery_app, 'send_task', side_effect=OSError('connection refused')
        ):
            with self.assertRaises(OSError):
                send_test_notification.delay('nobody home')

    def test_a_caller_can_queue_without_risking_the_request(self):
        """The shape every caller from Slice 7 on will use.

        Written here, against the trivial task, so the pattern is established
        before a booking depends on it.
        """
        queued = []

        def queue_safely(message):
            try:
                send_test_notification.delay(message)
                queued.append(message)
            except Exception:  # noqa: BLE001 - deliberately broad
                # The work is lost; the request is not.
                return False
            return True

        with mock.patch.object(
            send_test_notification, 'delay', side_effect=OSError('down')
        ):
            self.assertFalse(queue_safely('x'))
        self.assertEqual(queued, [])


class RealBrokerTests(SimpleTestCase):
    """Against an actual Redis, when one is there.

    Skipped locally where there is no broker, and run in CI, where the
    Postgres job has one as a service. Without this the Redis service in CI
    is decoration: everything else in this file runs eagerly or against a
    mock, and none of it would notice if the broker configuration were wrong
    in a way only a real connection reveals.

    It publishes rather than executes — there is no worker in CI — which is
    exactly the half a request does.
    """

    def setUp(self):
        try:
            connection = celery_app.connection_for_write()
            connection.ensure_connection(max_retries=0, timeout=2)
            connection.release()
        except Exception:  # noqa: BLE001 - any failure means "no broker here"
            self.skipTest('no broker reachable')

    @override_settings(CELERY_TASK_ALWAYS_EAGER=False)
    def test_a_task_can_actually_be_published(self):
        result = send_test_notification.delay('over the wire')

        # No worker is running, so it will never finish. That it was accepted
        # by the broker at all is the thing being checked.
        self.assertIsNotNone(result.id)
