# Synthetic compliant fixture for Gate G09.2 Hadolint positive testing
# Adheres strictly to container security best practices:
# 1. Pinned immutable digest
# 2. Non-root user creation and execution
# 3. Workdir set properly
# 4. Explicit cache management

FROM alpine:3.21.3@sha256:a8560b36e8b8210634f77d9f7f9efd7ffa463e380b75e2e74aff4511df3ef88c

RUN addgroup -g 10001 -S appgroup && \
    adduser -u 10001 -S appuser -G appgroup

WORKDIR /app
USER 10001:10001

CMD ["echo", "ForgeOps compliant container"]
