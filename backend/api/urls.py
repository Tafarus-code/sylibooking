from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .auth import LoginView, LogoutView, MeView
from .customer_views import (
    CancelReservationByReferenceView,
    PaymentStatusView,
    ReservationByReferenceView,
)
from .views import EstablishmentViewSet, ReservationViewSet

router = DefaultRouter()
router.register('establishments', EstablishmentViewSet, basename='establishment')
router.register('reservations', ReservationViewSet, basename='reservation')

urlpatterns = [
    path('auth/login/', LoginView.as_view(), name='auth-login'),
    path('auth/logout/', LogoutView.as_view(), name='auth-logout'),
    path('auth/me/', MeView.as_view(), name='auth-me'),
    # Registered before the router so "ref" is not swallowed by the viewset's
    # detail route as a primary key.
    path(
        'reservations/ref/<uuid:reference>/',
        ReservationByReferenceView.as_view(),
        name='reservation-by-reference',
    ),
    path(
        'reservations/ref/<uuid:reference>/cancel/',
        CancelReservationByReferenceView.as_view(),
        name='reservation-cancel-by-reference',
    ),
    path(
        'reservations/ref/<uuid:reference>/payment/',
        PaymentStatusView.as_view(),
        name='reservation-payment-status',
    ),
    path('', include(router.urls)),
]