package com.forgeops.forgetasks;

import com.forgeops.forgetasks.account.dto.AccountRegistrationRequest;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;

import java.util.UUID;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class AccountApiIntegrationTest extends AbstractIntegrationTest {

    @Test
    @DisplayName("POST /api/v1/accounts: successfully registers user, rejects duplicate with 409")
    void shouldRegisterAccountAndEnforceUniqueness() throws Exception {
        String uniqueUser = "testuser_" + UUID.randomUUID().toString().substring(0, 8);
        AccountRegistrationRequest req = new AccountRegistrationRequest(uniqueUser, "StrongPassword123!");

        // 1. Success registration -> 201 Created
        mockMvc.perform(post("/api/v1/accounts")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(req)))
                .andExpect(status().isCreated())
                .andExpect(header().exists("Location"))
                .andExpect(header().exists("X-Request-ID"))
                .andExpect(jsonPath("$.id").isNotEmpty())
                .andExpect(jsonPath("$.username").value(uniqueUser))
                .andExpect(jsonPath("$.role").value("ROLE_USER"));

        // 2. Duplicate registration attempt -> 409 Conflict
        mockMvc.perform(post("/api/v1/accounts")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(req)))
                .andExpect(status().isConflict())
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.title").value("Conflict"))
                .andExpect(jsonPath("$.detail").value(org.hamcrest.Matchers.containsString("already registered")));
    }

    @Test
    @DisplayName("POST /api/v1/accounts: validation rejection on invalid input")
    void shouldRejectInvalidRegistration() throws Exception {
        AccountRegistrationRequest badReq = new AccountRegistrationRequest("ab", "short");

        mockMvc.perform(post("/api/v1/accounts")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(badReq)))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.title").value("Validation Failure"))
                .andExpect(jsonPath("$.invalidParams").exists());
    }
}
