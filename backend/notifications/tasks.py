"""Work that happens away from a request.

Tasks live in their own app rather than accreting inside `api/`: they are not
endpoints, they outlive the request that queued them, and mixing the two makes
it hard to see what actually runs on a worker.

Two rules everything here follows.

A task takes ids, not objects. The row may have changed between queueing and
running — that gap is the whole point of a queue — so a task re-reads what it
needs and decides then.

A task that cannot do its job says so by raising, and lets the retry policy
decide. Swallowing the error means a reminder that never arrives and nothing
anywhere recording that it did not.
"""

import logging

from celery import shared_task

logger = logging.getLogger(__name__)


@shared_task(
    bind=True,
    max_retries=3,
    default_retry_delay=30,
    autoretry_for=(Exception,),
    retry_backoff=True,
)
def send_test_notification(self, message='ping'):
    """Prove the wiring, and nothing else.

    Exists so this slice can be verified end to end — queue it from a shell,
    watch a worker log it — without any real behaviour riding on a queue that
    has never been run in anger.
    """
    logger.info('Task queue reached: %s', message)
    return message
