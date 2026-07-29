from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .auth import LoginView, LogoutView, MeView
from .customer_views import (
    CancelReservationByReferenceView,
    PaymentStatusView,
    ReservationByReferenceView,
)
from .dashboard import PaymentDashboardView
from .merchant import (
    MerchantEstablishmentProfileView,
    MerchantEstablishmentsView,
    MerchantHoursView,
    MerchantMenuAvailabilityView,
    MerchantMenuItemView,
    MerchantMenuView,
    MerchantStaffMemberView,
    MerchantStaffView,
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
    path(
        'dashboard/payments/',
        PaymentDashboardView.as_view(),
        name='payment-dashboard',
    ),
    # Merchant-facing. Every route carries the establishment id, and every
    # handler checks membership against it.
    path(
        'merchant/establishments/',
        MerchantEstablishmentsView.as_view(),
        name='merchant-establishments',
    ),
    path(
        'merchant/establishments/<int:pk>/',
        MerchantEstablishmentProfileView.as_view(),
        name='merchant-establishment-profile',
    ),
    path(
        'merchant/establishments/<int:pk>/hours/',
        MerchantHoursView.as_view(),
        name='merchant-hours',
    ),
    path(
        'merchant/establishments/<int:pk>/menu/',
        MerchantMenuView.as_view(),
        name='merchant-menu',
    ),
    path(
        'merchant/establishments/<int:pk>/menu/<int:item_id>/',
        MerchantMenuItemView.as_view(),
        name='merchant-menu-item',
    ),
    path(
        'merchant/establishments/<int:pk>/menu/<int:item_id>/availability/',
        MerchantMenuAvailabilityView.as_view(),
        name='merchant-menu-availability',
    ),
    path(
        'merchant/establishments/<int:pk>/staff/',
        MerchantStaffView.as_view(),
        name='merchant-staff',
    ),
    path(
        'merchant/establishments/<int:pk>/staff/<int:membership_id>/',
        MerchantStaffMemberView.as_view(),
        name='merchant-staff-member',
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