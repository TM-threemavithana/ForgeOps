# syntax=docker/dockerfile:1
# ForgeTasks REST API — Multi-Stage Containerfile
# Aligned with ForgeOps Gate G02 Containerization and Security Baseline

# ------------------------------------------------------------------------------
# Stage 1: Build stage (pinned immutable multi-arch digest)
# ------------------------------------------------------------------------------
FROM eclipse-temurin:21-jdk-alpine@sha256:82801f9dcdcbad5a05082aba8c86d1da5b72ccb498e71318b1f91b5a477887b3 AS builder

WORKDIR /build

# Copy Maven Wrapper and POM first to leverage BuildKit layer caching for dependencies
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./

# Pre-fetch project dependencies in a dedicated cached layer
RUN ./mvnw dependency:go-offline -B || true

# Copy source tree
COPY src/ src/

# Build and package the Spring Boot executable fat JAR without running tests
# (Integration and coverage tests are independently verified in the G01 test lifecycle)
RUN ./mvnw clean package -DskipTests -B

# ------------------------------------------------------------------------------
# Stage 2: Minimal hardened runtime stage (pinned immutable multi-arch digest)
# ------------------------------------------------------------------------------
FROM eclipse-temurin:21-jre-alpine@sha256:ac05c3c42b7c2f1a52c9bd52f01041fa1958231b15ebeae7420429cbc5baf474 AS runtime

# OCI Image Annotations (Standardized Metadata)
LABEL org.opencontainers.image.title="ForgeTasks API" \
      org.opencontainers.image.description="ForgeTasks REST API and Persistence Service for ForgeOps DevOps Lab" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.vendor="ForgeOps Platform Engineering" \
      org.opencontainers.image.licenses="Apache-2.0"

# Security: Apply upstream security patches and create unprivileged non-root user
RUN apk upgrade --no-cache brotli-libs libexpat && \
    addgroup -g 10001 -S appgroup && \
    adduser -u 10001 -S appuser -G appgroup

WORKDIR /app

# Copy only the compiled Spring Boot fat JAR from the builder stage
# Ensure ownership is assigned to the non-root user
COPY --from=builder --chown=appuser:appgroup /build/target/forgetasks-api-*.jar /app/forgetasks-api.jar

# Enforce non-root execution
USER 10001:10001

# Standard container HTTP port
EXPOSE 8080

# Execute Spring Boot application using exec-form with container-aware JVM ergonomics
ENTRYPOINT ["java", \
            "-XX:+UseContainerSupport", \
            "-XX:MaxRAMPercentage=75.0", \
            "-XX:InitialRAMPercentage=50.0", \
            "-Djava.security.egd=file:/dev/./urandom", \
            "-jar", "/app/forgetasks-api.jar"]
