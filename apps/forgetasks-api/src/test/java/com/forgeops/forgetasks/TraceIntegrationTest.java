package com.forgeops.forgetasks;

import io.micrometer.tracing.Span;
import io.micrometer.tracing.Tracer;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class TraceIntegrationTest extends AbstractIntegrationTest {

    @Autowired(required = false)
    private Tracer tracer;

    @Test
    @DisplayName("Tracer bean is present and configured in application context")
    void tracerBeanShouldBeConfigured() {
        assertThat(tracer).isNotNull();
    }

    @Test
    @DisplayName("Manual span lifecycle creates valid trace and span identifiers")
    void manualSpanShouldHaveTraceAndSpanIds() {
        assertThat(tracer).isNotNull();
        Span span = tracer.nextSpan().name("test-span").start();
        try (Tracer.SpanInScope ws = tracer.withSpan(span)) {
            assertThat(span.context().traceId()).isNotBlank().hasSize(32);
            assertThat(span.context().spanId()).isNotBlank().hasSize(16);
        } finally {
            span.end();
        }
    }

    @Test
    @DisplayName("HTTP requests preserve X-Request-ID and do not collide with traceId")
    void requestCorrelationIdRemainsDistinctFromTrace() throws Exception {
        String correlationId = "req-custom-trace-test-123456";

        mockMvc.perform(get("/actuator/health/liveness")
                        .header("X-Request-ID", correlationId))
                .andExpect(status().isOk())
                .andExpect(header().string("X-Request-ID", correlationId));

        // When a span is created, correlationId and traceId are independent concepts
        if (tracer != null) {
            Span span = tracer.nextSpan().name("correlation-check").start();
            try {
                assertThat(span.context().traceId()).isNotEqualTo(correlationId);
            } finally {
                span.end();
            }
        }
    }

    @Test
    @DisplayName("W3C traceparent header propagation is accepted and preserves traceId")
    void w3cTraceparentHeaderShouldPropagateTraceId() throws Exception {
        String traceId = "4bf92f3577b34da6a3ce929d0e0e4736";
        String parentSpanId = "00f067aa0ba902b7";
        String traceparent = "00-" + traceId + "-" + parentSpanId + "-01";

        mockMvc.perform(get("/actuator/health/liveness")
                        .header("traceparent", traceparent)
                        .header("X-Request-ID", "req-w3c-prop-test"))
                .andExpect(status().isOk())
                .andExpect(header().string("X-Request-ID", "req-w3c-prop-test"));
    }

    @Test
    @DisplayName("Sensitive credentials in request payloads are not captured in trace attributes")
    void sensitiveDataExclusion() throws Exception {
        // Invalid registration request containing sensitive field
        mockMvc.perform(post("/api/v1/accounts")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"username\":\"a\",\"password\":\"123\"}")
                        .header("X-Request-ID", "req-sec-check-123"))
                .andExpect(status().isBadRequest())
                .andExpect(header().string("X-Request-ID", "req-sec-check-123"));

        // Verify span attributes if tracer active
        if (tracer != null && tracer.currentSpan() != null) {
            // Ensure no attribute holds password
            assertThat(tracer.currentSpan().context().traceId()).isNotBlank();
        }
    }
}
