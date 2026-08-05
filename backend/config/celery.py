"""The task queue, so work that is not a request stops living inside one.

Deliberately introduced with nothing on it. A slice that adds infrastructure
*and* the features that need it is a slice where a failure is ambiguous: was
the reminder wrong, or was the queue never running? This one is boring on
purpose, and the reminders that need it come next.

Run a worker with:  celery -A config worker --loglevel=info
And the scheduler with:  celery -A config beat --loglevel=info
"""

import os

from celery import Celery

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')

app = Celery('sylibooking')

# Settings are read from Django's own, namespaced, so there is one place a
# deployment is configured rather than two.
app.config_from_object('django.conf:settings', namespace='CELERY')
app.autodiscover_tasks()
