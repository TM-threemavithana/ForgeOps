# syntax=docker/dockerfile:1
# ForgeTasks REST API — Multi-Stage Containerfile
# Aligned with ForgeOps Gate G02 Containerization and Security Baseline

# ------------------------------------------------------------------------------
# Stage 1: Build stage
# ------------------------------------------------------------------------------
FROM eclipse-temurin:25-jdk-alpine AS builder

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
# Stage 2: Minimal hardened runtime stage
# ------------------------------------------------------------------------------
FROM eclipse-temurin:25-jre-alpine AS runtime

# OCI Image Annotations (Standardized Metadata)
LABEL org.opencontainers.image.title="ForgeTasks API" \
      org.opencontainers.image.description="ForgeTasks REST API and Persistence Service for ForgeOps DevOps Lab" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.vendor="ForgeOps Platform Engineering" \
      org.opencontainers.image.licenses="Apache-2.0"

# Security: Apply upstream security patches and create unprivileged non-root user
RUN apk upgrade --no-cache brotli-libs && \
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
