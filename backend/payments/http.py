"""One HTTP client for every provider we talk to.

Timeouts, retries and error mapping decided once rather than four times.
Every integration in this project — Orange, MTN, the SMS gateway, WhatsApp —
is the same shape: get a token, post a request, read a status.

Two rules that matter more here than anywhere else in the codebase.

**A timeout is not a failure.** When a payment request times out, the money
may well be moving; we simply did not hear back. Callers get a distinct
exception so they can leave a payment pending rather than telling a customer
it went wrong and taking it again.

**Reads are retried, writes are not.** The same rule as the Dart client, for
the same reason: a retried "request to pay" is two prompts on somebody's
phone and possibly two debits. Only status checks and token fetches — which
change nothing — are asked twice.
"""

import logging
import time

import requests

logger = logging.getLogger(__name__)

#: Long enough for a mobile money gateway on a bad day, short enough that a
#: worker is not held all afternoon by one unanswered call.
DEFAULT_TIMEOUT = 20

#: Reads only. Two extra attempts, backing off, then give up.
READ_RETRIES = 2


class ProviderHttpError(Exception):
    """The request could not be completed. We do not know the outcome."""

    def __init__(self, message, *, status_code=None, body=None):
        super().__init__(message)
        self.status_code = status_code
        self.body = body


class ProviderTimeout(ProviderHttpError):
    """No answer in time. Distinct because the request may still be running."""


class ProviderRefused(ProviderHttpError):
    """The provider answered, and the answer was no.

    A 4xx is the provider telling us something about the request — a bad
    number, an expired token, insufficient funds. Retrying it changes
    nothing, and the body usually says why.
    """


def request(
    method,
    url,
    *,
    session=None,
    idempotent=False,
    timeout=DEFAULT_TIMEOUT,
    retries=READ_RETRIES,
    **kwargs,
):
    """Perform one provider call and hand back the parsed JSON.

    `idempotent` decides whether it may be retried, and the caller decides
    that — not the HTTP verb. A POST that only reads a status is safe to
    repeat; a GET that starts something would not be, if one existed.
    """
    caller = session or requests
    attempts = (retries + 1) if idempotent else 1
    last_error = None

    for attempt in range(1, attempts + 1):
        try:
            response = caller.request(method, url, timeout=timeout, **kwargs)
        except requests.Timeout:
            last_error = ProviderTimeout(f'{method} {url} timed out')
            logger.warning('provider timeout: %s %s', method, url)
        except requests.RequestException as error:
            last_error = ProviderHttpError(f'{method} {url} failed: {error}')
            logger.warning('provider unreachable: %s %s (%s)', method, url, error)
        else:
            return _read(response, method, url)

        if attempt < attempts:
            # Backing off rather than hammering: a gateway that just refused a
            # connection is usually busy, not broken.
            time.sleep(0.5 * (2 ** (attempt - 1)))

    raise last_error


def _read(response, method, url):
    if response.status_code >= 500:
        # Their side. Worth telling apart from a refusal because a 500 is
        # worth another attempt later and a 400 never is.
        raise ProviderHttpError(
            f'{method} {url} returned {response.status_code}',
            status_code=response.status_code,
            body=response.text[:2000],
        )
    if response.status_code >= 400:
        raise ProviderRefused(
            f'{method} {url} returned {response.status_code}',
            status_code=response.status_code,
            body=response.text[:2000],
        )

    if not response.content:
        return {}
    try:
        return response.json()
    except ValueError:
        # Some gateways answer 200 with a plain-text body. Hand it back
        # rather than raising: the caller knows what it asked for.
        return {'raw': response.text}
