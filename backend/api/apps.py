from django.apps import AppConfig


class ApiConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'api'

    def ready(self):
        # Importing registers the project's own deployment checks. Done here
        # rather than in settings because a check needs the app registry, and
        # settings runs before there is one.
        from config import checks  # noqa: F401
