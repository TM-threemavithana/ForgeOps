package com.forgeops.forgetasks.common.correlation;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.slf4j.MDC;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import java.io.IOException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;

@ExtendWith(MockitoExtension.class)
class RequestCorrelationFilterTest {

    private RequestCorrelationFilter filter;

    @Mock
    private FilterChain filterChain;

    @BeforeEach
    void setUp() {
        filter = new RequestCorrelationFilter();
        MDC.clear();
    }

    @Test
    @DisplayName("Should accept and propagate valid incoming X-Request-ID")
    void shouldPropagateValidCorrelationId() throws ServletException, IOException {
        MockHttpServletRequest request = new MockHttpServletRequest();
        MockHttpServletResponse response = new MockHttpServletResponse();
        String validId = "req-12345678-abcd";
        request.addHeader(RequestCorrelationFilter.CORRELATION_ID_HEADER, validId);

        filter.doFilterInternal(request, response, filterChain);

        assertThat(response.getHeader(RequestCorrelationFilter.CORRELATION_ID_HEADER)).isEqualTo(validId);
        assertThat(MDC.get(RequestCorrelationFilter.MDC_CORRELATION_KEY)).isNull(); // Cleared in finally
        verify(filterChain).doFilter(request, response);
    }

    @Test
    @DisplayName("Should generate new correlation ID when incoming header is missing or malformed")
    void shouldGenerateNewCorrelationIdWhenMissingOrMalformed() throws ServletException, IOException {
        MockHttpServletRequest request = new MockHttpServletRequest();
        MockHttpServletResponse response = new MockHttpServletResponse();
        request.addHeader(RequestCorrelationFilter.CORRELATION_ID_HEADER, "invalid id with spaces & \n injection");

        filter.doFilterInternal(request, response, filterChain);

        String generatedId = response.getHeader(RequestCorrelationFilter.CORRELATION_ID_HEADER);
        assertThat(generatedId).isNotNull().isNotBlank().isNotEqualTo("invalid id with spaces & \n injection");
        assertThat(MDC.get(RequestCorrelationFilter.MDC_CORRELATION_KEY)).isNull();
        verify(filterChain).doFilter(request, response);
    }
}
