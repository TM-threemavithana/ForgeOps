package com.forgeops.forgetasks;

import com.forgeops.forgetasks.account.dto.AccountRegistrationRequest;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;

import java.util.UUID;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class SecurityIntegrationTest extends AbstractIntegrationTest {

    @Test
    @DisplayName("Security: Unauthenticated request to protected API returns 401 with RFC 9457 ProblemDetail")
    void shouldReturn401ForUnauthenticatedRequest() throws Exception {
        mockMvc.perform(get("/api/v1/projects"))
                .andExpect(status().isUnauthorized())
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.title").value("Unauthorized"))
                .andExpect(jsonPath("$.correlationId").exists());
    }

    @Test
    @DisplayName("Security: Bad credentials return 401 with RFC 9457 ProblemDetail")
    void shouldReturn401ForBadCredentials() throws Exception {
        String badAuth = basicAuthHeader("nonexistent_user", "wrong_pass");
        mockMvc.perform(get("/api/v1/projects")
                        .header(HttpHeaders.AUTHORIZATION, badAuth))
                .andExpect(status().isUnauthorized())
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.title").value("Unauthorized"));
    }

    @Test
    @DisplayName("Security: Regular USER role cannot access privileged Actuator endpoints (403 Forbidden)")
    void shouldDenyPrivilegedActuatorForRegularUser() throws Exception {
        String user = "reg_user_" + UUID.randomUUID().toString().substring(0, 8);
        String pass = "Password123!";

        mockMvc.perform(post("/api/v1/accounts")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new AccountRegistrationRequest(user, pass))))
                .andExpect(status().isCreated());

        String auth = basicAuthHeader(user, pass);

        mockMvc.perform(get("/actuator/beans")
                        .header(HttpHeaders.AUTHORIZATION, auth))
                .andExpect(status().isForbidden())
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.title").value("Forbidden"));
    }
}
