# A Flutter app, built for the web and served by nginx.
#
# One file for both apps: which one is built is the APP build argument, so
# the merchant and customer services differ by a variable rather than by a
# duplicated Dockerfile that will drift.
#
# **This is a second distribution channel, not a replacement for the stores.**
# The Android builds remain how most people will use this — see RELEASE.md.
# What the web build buys is a venue with a laptop and no wish to install
# anything, and a link somebody can open before they have decided to trust
# you enough to install an app.
#
#   docker build -f deploy/flutter-web.Dockerfile \
#     --build-arg APP=merchant_app \
#     --build-arg API_BASE_URL=https://api.sylibooking.gn/api \
#     -t sylibooking-merchant-web .
#
# The build context is the repository root, because `shared_client` is a path
# dependency of both apps and lives beside them. The root .dockerignore
# excludes apps/ for the backend image's sake, so this file has its own —
# see flutter-web.Dockerfile.dockerignore.

ARG FLUTTER_VERSION=3.38.5

FROM ghcr.io/cirruslabs/flutter:${FLUTTER_VERSION} AS build

# Which app. No default: building the wrong one and finding out from the
# login screen is a worse afternoon than a failed build.
ARG APP
RUN test -n "$APP" || (echo "APP build argument is required" && exit 1)

# Where this build talks to. Baked in at compile time, because a web build
# has no equivalent of an emulator's 10.0.2.2 and no settings screen to ask.
# Wrong here means an app that loads and can do nothing.
ARG API_BASE_URL

# Checked at build time, because nothing downstream treats a bad value as an
# error. Dart's Uri.parse reads "api.example.com/api" as a *relative path*, so
# every request is resolved against the page's own origin and the app calls
# itself: POST gets 405 from nginx, GET gets index.html and a spinner that
# never resolves. Neither symptom points anywhere near this variable.
#
# The trailing-slash case is the same class of quiet wrong: the client builds
# URLs as "$baseUrl$path" and every path already starts with "/".
RUN set -e; \
    if [ -z "$API_BASE_URL" ]; then \
        echo "API_BASE_URL build argument is required"; \
        echo "  e.g. --build-arg API_BASE_URL=https://api.example.com/api"; \
        exit 1; \
    fi; \
    case "$API_BASE_URL" in \
        http://*|https://*) ;; \
        *) \
            echo "API_BASE_URL must be absolute, starting http:// or https://"; \
            echo "  got: '$API_BASE_URL'"; \
            echo "  without a scheme every request is sent to the app's own origin."; \
            exit 1 ;; \
    esac; \
    case "$API_BASE_URL" in \
        */) \
            echo "API_BASE_URL must not end in '/'"; \
            echo "  got: '$API_BASE_URL'"; \
            echo "  request paths already begin with one."; \
            exit 1 ;; \
    esac; \
    # And the third shape of quiet wrong: the bare host, with the path left
    # off. Django mounts the whole API under /api/ (config/urls.py), so a
    # host-only base sends every call one level too high — /auth/login/
    # instead of /api/auth/login/ — and each returns a 404 *page*, which the
    # app then has to show somebody. Nothing here is served from the root, so
    # there is no build for which a bare host is right.
    host_and_path="${API_BASE_URL#*://}"; \
    case "$host_and_path" in \
        */*) ;; \
        *) \
            echo "API_BASE_URL is missing its path"; \
            echo "  got:  '$API_BASE_URL'"; \
            echo "  want: '$API_BASE_URL/api'"; \
            echo "  the API is mounted under /api/, so a bare host 404s."; \
            exit 1 ;; \
    esac

WORKDIR /src
# The shared package first, so a change to an app does not re-resolve it.
COPY apps/shared_client /src/apps/shared_client
COPY apps/${APP} /src/apps/${APP}

WORKDIR /src/apps/${APP}
RUN flutter pub get
RUN flutter build web --release \
    --dart-define=API_BASE_URL="${API_BASE_URL}"

# Pre-compressed, because the payload is the whole argument here: the main
# bundle is about 8MB raw and 1.5MB gzipped, and this market pays for every
# one of those megabytes. gzip_static below serves these without spending CPU
# per request.
RUN find build/web -type f \
        \( -name '*.js' -o -name '*.css' -o -name '*.html' \
           -o -name '*.json' -o -name '*.wasm' -o -name '*.svg' \) \
        -exec gzip -9 -k {} \;


FROM nginx:1.27-alpine AS runtime

# nginx's own template mechanism: files here are envsubst'd into conf.d at
# startup, which is how the container learns the port the platform routes to.
COPY deploy/flutter-web.nginx.conf.template /etc/nginx/templates/default.conf.template

ARG APP
COPY --from=build /src/apps/${APP}/build/web /usr/share/nginx/html

ENV PORT=8080
EXPOSE 8080
