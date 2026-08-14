"""Django project package.

Importing the Celery app here is what makes `@shared_task` bind to it: Django
loads this package before anything else, so a task defined in any app finds a
configured broker rather than a default one.
"""

from .celery import app as celery_app

__all__ = ('celery_app',)
