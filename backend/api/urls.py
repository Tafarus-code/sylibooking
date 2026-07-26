from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .auth import LoginView, LogoutView, MeView
from .views import EstablishmentViewSet, ReservationViewSet

router = DefaultRouter()
router.register('establishments', EstablishmentViewSet, basename='establishment')
router.register('reservations', ReservationViewSet, basename='reservation')

urlpatterns = [
    path('auth/login/', LoginView.as_view(), name='auth-login'),
    path('auth/logout/', LogoutView.as_view(), name='auth-logout'),
    path('auth/me/', MeView.as_view(), name='auth-me'),
    path('', include(router.urls)),
]