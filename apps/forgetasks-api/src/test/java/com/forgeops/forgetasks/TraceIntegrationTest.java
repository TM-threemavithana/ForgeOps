package com.forgeops.forgetasks;

import io.micrometer.tracing.Span;
import io.micrometer.tracing.Tracer;
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.context.Context;
import io.opentelemetry.sdk.trace.ReadWriteSpan;
import io.opentelemetry.sdk.trace.ReadableSpan;
import io.opentelemetry.sdk.trace.SpanProcessor;
import io.opentelemetry.sdk.trace.data.EventData;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;

import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@Import(TraceIntegrationTest.SpanTestConfig.class)
class TraceIntegrationTest extends AbstractIntegrationTest {

    @Autowired
    private Tracer tracer;

    @Autowired
    private TestSpanProcessor testSpanProcessor;

    @BeforeEach
    void clearSpans() {
        testSpanProcessor.clear();
    }

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

        assertThat(testSpanProcessor.getSpans()).isNotEmpty();
        ReadableSpan endedSpan = testSpanProcessor.getSpans().stream()
                .filter(s -> "test-span".equals(s.getName()))
                .findFirst()
                .orElse(null);
        assertThat(endedSpan).isNotNull();
        assertThat(endedSpan.getSpanContext().getTraceId()).hasSize(32);
    }

    @Test
    @DisplayName("HTTP requests preserve X-Request-ID and do not collide with traceId")
    void requestCorrelationIdRemainsDistinctFromTrace() throws Exception {
        String correlationId = "req-custom-trace-test-123456";

        mockMvc.perform(get("/actuator/health/liveness")
                        .header("X-Request-ID", correlationId))
                .andExpect(status().isOk())
                .andExpect(header().string("X-Request-ID", correlationId));

        assertThat(testSpanProcessor.getSpans()).isNotEmpty();
        for (ReadableSpan span : testSpanProcessor.getSpans()) {
            assertThat(span.getSpanContext().getTraceId())
                    .as("TraceId must be distinct from X-Request-ID correlationId")
                    .isNotEqualTo(correlationId);
            assertThat(span.getSpanContext().getTraceId())
                    .as("TraceId must be a 32-character hexadecimal string")
                    .hasSize(32);
        }
    }

    @Test
    @DisplayName("W3C traceparent header propagation is accepted and preserves traceId on server span")
    void w3cTraceparentHeaderShouldPropagateTraceId() throws Exception {
        String incomingTraceId = "4bf92f3577b34da6a3ce929d0e0e4736";
        String incomingParentSpanId = "00f067aa0ba902b7";
        String traceparent = "00-" + incomingTraceId + "-" + incomingParentSpanId + "-01";

        mockMvc.perform(get("/actuator/health/liveness")
                        .header("traceparent", traceparent)
                        .header("X-Request-ID", "req-w3c-prop-test"))
                .andExpect(status().isOk())
                .andExpect(header().string("X-Request-ID", "req-w3c-prop-test"));

        List<ReadableSpan> capturedSpans = testSpanProcessor.getSpans();
        assertThat(capturedSpans).isNotEmpty();

        ReadableSpan serverSpan = capturedSpans.stream()
                .filter(s -> s.getKind() == SpanKind.SERVER)
                .findFirst()
                .orElse(null);

        assertThat(serverSpan)
                .as("A SERVER span must be recorded for the incoming HTTP request")
                .isNotNull();

        assertThat(serverSpan.getSpanContext().getTraceId())
                .as("The server span must preserve the trace ID from the incoming W3C traceparent")
                .isEqualTo(incomingTraceId);

        assertThat(serverSpan.getParentSpanContext().getSpanId())
                .as("The server span must preserve the parent span ID from the incoming W3C traceparent")
                .isEqualTo(incomingParentSpanId);
    }

    @Test
    @DisplayName("Sensitive credentials in request payloads and headers are not captured in trace attributes or events")
    void sensitiveDataExclusion() throws Exception {
        String sensitivePassword = "super-secret-password-xyz-987";
        String sensitiveToken = "bearer-secret-token-abc-123";

        // Registration request containing sensitive payload and authorization header
        mockMvc.perform(post("/api/v1/accounts")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"username\":\"a\",\"password\":\"" + sensitivePassword + "\"}")
                        .header("Authorization", "Bearer " + sensitiveToken)
                        .header("X-Request-ID", "req-sec-check-123"))
                .andExpect(status().isBadRequest())
                .andExpect(header().string("X-Request-ID", "req-sec-check-123"));

        List<ReadableSpan> capturedSpans = testSpanProcessor.getSpans();
        assertThat(capturedSpans).isNotEmpty();

        for (ReadableSpan span : capturedSpans) {
            Map<AttributeKey<?>, Object> attributes = span.getAttributes().asMap();
            for (Map.Entry<AttributeKey<?>, Object> entry : attributes.entrySet()) {
                String keyStr = entry.getKey().getKey().toLowerCase();
                String valStr = String.valueOf(entry.getValue()).toLowerCase();

                assertThat(valStr)
                        .as("Span attribute '%s' must not contain sensitive password", keyStr)
                        .doesNotContain(sensitivePassword.toLowerCase());
                assertThat(valStr)
                        .as("Span attribute '%s' must not contain sensitive bearer token", keyStr)
                        .doesNotContain(sensitiveToken.toLowerCase());
            }

            for (EventData event : span.toSpanData().getEvents()) {
                String eventName = event.getName().toLowerCase();
                String eventAttrs = event.getAttributes().asMap().toString().toLowerCase();

                assertThat(eventName)
                        .doesNotContain(sensitivePassword.toLowerCase())
                        .doesNotContain(sensitiveToken.toLowerCase());
                assertThat(eventAttrs)
                        .doesNotContain(sensitivePassword.toLowerCase())
                        .doesNotContain(sensitiveToken.toLowerCase());
            }
        }
    }

    @TestConfiguration
    static class SpanTestConfig {
        @Bean
        TestSpanProcessor testSpanProcessor() {
            return new TestSpanProcessor();
        }
    }

    static class TestSpanProcessor implements SpanProcessor {
        private final List<ReadableSpan> spans = new CopyOnWriteArrayList<>();

        @Override
        public void onStart(Context parentContext, ReadWriteSpan span) {
        }

        @Override
        public boolean isStartRequired() {
            return false;
        }

        @Override
        public void onEnd(ReadableSpan span) {
            spans.add(span);
        }

        @Override
        public boolean isEndRequired() {
            return true;
        }

        public List<ReadableSpan> getSpans() {
            return spans;
        }

        public void clear() {
            spans.clear();
        }
    }
}
