package com.forgeops.forgetasks;

import org.hamcrest.Matchers;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class ObservabilityIntegrationTest extends AbstractIntegrationTest {

    @Test
    @DisplayName("Liveness probe: /actuator/health/liveness returns 200 UP without DB dependency")
    void shouldReportLivenessUp() throws Exception {
        mockMvc.perform(get("/actuator/health/liveness"))
                .andExpect(status().isOk())
                .andExpect(header().exists("X-Request-ID"))
                .andExpect(jsonPath("$.status").value("UP"));
    }

    @Test
    @DisplayName("Readiness probe: /actuator/health/readiness returns 200 UP when PostgreSQL is available")
    void shouldReportReadinessUp() throws Exception {
        mockMvc.perform(get("/actuator/health/readiness"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }

    @Test
    @DisplayName("Prometheus metrics: /actuator/prometheus scrapes Prometheus format metrics")
    void shouldExposePrometheusMetrics() throws Exception {
        mockMvc.perform(get("/actuator/prometheus"))
                .andExpect(status().isOk())
                .andExpect(content().string(Matchers.containsString("jvm_memory_used_bytes")));
    }
}
