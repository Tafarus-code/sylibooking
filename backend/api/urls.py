from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .auth import LoginView, LogoutView, MeView
from .customer_views import (
    CancelReservationByReferenceView,
    PaymentStatusView,
    ReservationByReferenceView,
)
from .reviews import EstablishmentPhotosView, EstablishmentReviewsView
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
    # Before the router, so these are not taken for viewset detail routes.
    path(
        'establishments/<int:pk>/reviews/',
        EstablishmentReviewsView.as_view(),
        name='establishment-reviews',
    ),
    path(
        'establishments/<int:pk>/photos/',
        EstablishmentPhotosView.as_view(),
        name='establishment-photos',
    ),
    path('', include(router.urls)),
]