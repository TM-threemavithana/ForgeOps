# Synthetic isolated fixture for Gate G09.2 Hadolint failure testing
# Deliberately violates container security best practices:
# 1. Unpinned floating 'latest' tag (DL3007)
# 2. Missing --no-cache on apk (DL3019)
# 3. Running as root user as final user (DL3002)
# 4. Use of sudo in container (DL3004)

FROM alpine:latest
RUN apk update && apk add curl sudo
ADD https://example.com/untrusted.tar.gz /tmp/untrusted.tar.gz
USER root
