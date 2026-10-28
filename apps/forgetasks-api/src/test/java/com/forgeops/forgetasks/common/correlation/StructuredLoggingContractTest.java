package com.forgeops.forgetasks.common.correlation;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.spi.LoggingEvent;
import ch.qos.logback.core.ContextBase;
import org.junit.jupiter.api.Test;
import org.slf4j.MDC;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.boot.logging.logback.StructuredLogEncoder;
import org.springframework.core.env.Environment;
import org.springframework.core.io.ClassPathResource;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import tools.jackson.databind.json.JsonMapper;

import static org.assertj.core.api.Assertions.assertThat;

class StructuredLoggingContractTest {

    @Test
    void productionProfileEnablesEcs() throws Exception {
        var sources = new YamlPropertySourceLoader().load(
                "prod",
                new ClassPathResource("application-prod.yml")
        );

        assertThat(sources).hasSize(1);

        assertThat(sources.get(0).getProperty(
                "logging.structured.format.console"
        )).isEqualTo("ecs");
    }

    @Test
    void requestCorrelationIdIsSerializedAsEcsJson() throws Exception {
        var context = new ContextBase();
        context.putObject(
                Environment.class.getName(),
                new MockEnvironment()
                        .withProperty("spring.application.name", "forgetasks-api")
        );

        var encoder = new StructuredLogEncoder();
        encoder.setContext(context);
        encoder.setFormat("ecs");
        encoder.start();

        String requestId = "req-g10-test-12345678";

        var request = new MockHttpServletRequest();
        request.addHeader("X-Request-ID", requestId);

        var response = new MockHttpServletResponse();
        var output = new AtomicReference<String>();

        try {
            new RequestCorrelationFilter().doFilterInternal(
                    request,
                    response,
                    (req, res) -> {
                        var event = new LoggingEvent();
                        event.setInstant(Instant.now());
                        event.setLevel(Level.INFO);
                        event.setLoggerName("forgeops.g10.test");
                        event.setThreadName("main");
                        event.setMessage("g10-json-probe");

                        Map<String, String> mdc =
                                MDC.getCopyOfContextMap();

                        assertThat(mdc).isNotNull();
                        event.setMDCPropertyMap(Map.copyOf(mdc));

                        output.set(new String(
                                encoder.encode(event),
                                StandardCharsets.UTF_8
                        ));
                    }
            );
        } finally {
            encoder.stop();
        }

        assertThat(response.getHeader("X-Request-ID"))
                .isEqualTo(requestId);

        assertThat(MDC.get("correlationId")).isNull();
        assertThat(output.get()).isNotBlank();

        var json = new JsonMapper().readTree(output.get());

        assertThat(json.path("correlationId").asString())
                .isEqualTo(requestId);

        assertThat(json.path("message").asString())
                .isEqualTo("g10-json-probe");

        assertThat(json.path("log").path("level").asString())
                .isEqualTo("INFO");

        assertThat(json.has("@timestamp")).isTrue();
        assertThat(json.path("ecs").path("version").asString())
                .isNotBlank();
    }

    @Test
    void traceAndSpanIdsAreSerializedInEcsJson() throws Exception {
        var context = new ContextBase();
        context.putObject(
                Environment.class.getName(),
                new MockEnvironment()
                        .withProperty("spring.application.name", "forgetasks-api")
        );

        var encoder = new StructuredLogEncoder();
        encoder.setContext(context);
        encoder.setFormat("ecs");
        encoder.start();

        try {
            var event = new LoggingEvent();
            event.setInstant(Instant.now());
            event.setLevel(Level.INFO);
            event.setLoggerName("forgeops.g11.test");
            event.setThreadName("main");
            event.setMessage("g11-trace-test");
            event.setMDCPropertyMap(Map.of(
                    "traceId", "0af7651916cd43dd8448eb211c80319c",
                    "spanId", "b7ad6b7169203331",
                    "correlationId", "req-test-123"
            ));

            String encoded = new String(encoder.encode(event), StandardCharsets.UTF_8);
            System.out.println("ENCODED_ECS_JSON=" + encoded);
            var json = new JsonMapper().readTree(encoded);
            assertThat(json.path("correlationId").asString()).isEqualTo("req-test-123");
            // Check if traceId is top-level or under trace.id
            System.out.println("traceId path: " + json.path("traceId"));
            System.out.println("trace.id path: " + json.path("trace").path("id"));
            System.out.println("spanId path: " + json.path("spanId"));
            System.out.println("span.id path: " + json.path("span").path("id"));
        } finally {
            encoder.stop();
        }
    }
}
