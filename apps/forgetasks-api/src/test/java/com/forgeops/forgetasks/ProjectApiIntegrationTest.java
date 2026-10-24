package com.forgeops.forgetasks;

import com.forgeops.forgetasks.account.dto.AccountRegistrationRequest;
import com.forgeops.forgetasks.project.dto.ProjectCreateRequest;
import com.forgeops.forgetasks.project.dto.ProjectResponse;
import com.forgeops.forgetasks.project.dto.ProjectUpdateRequest;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MvcResult;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class ProjectApiIntegrationTest extends AbstractIntegrationTest {

    private String userA;
    private String userB;
    private final String password = "Password1234!";

    @BeforeEach
    void setUpUsers() throws Exception {
        userA = "proj_user_a_" + UUID.randomUUID().toString().substring(0, 8);
        userB = "proj_user_b_" + UUID.randomUUID().toString().substring(0, 8);

        mockMvc.perform(post("/api/v1/accounts")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(new AccountRegistrationRequest(userA, password))))
                .andExpect(status().isCreated());

        mockMvc.perform(post("/api/v1/accounts")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(new AccountRegistrationRequest(userB, password))))
                .andExpect(status().isCreated());
    }

    @Test
    @DisplayName("Project API: CRUD, strong ETag, If-Match preconditions, and tenant isolation")
    void shouldPerformFullProjectLifecycle() throws Exception {
        String authA = basicAuthHeader(userA, password);
        String authB = basicAuthHeader(userB, password);

        // 1. User A creates project
        ProjectCreateRequest createReq = new ProjectCreateRequest("Kubernetes Engine", "Production cluster rollout");
        MvcResult createResult = mockMvc.perform(post("/api/v1/projects")
                        .header(HttpHeaders.AUTHORIZATION, authA)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(createReq)))
                .andExpect(status().isCreated())
                .andExpect(header().string(HttpHeaders.ETAG, "\"0\""))
                .andExpect(header().exists("X-Request-ID"))
                .andExpect(jsonPath("$.version").value(0))
                .andExpect(jsonPath("$.name").value("Kubernetes Engine"))
                .andReturn();

        ProjectResponse created = objectMapper.readValue(createResult.getResponse().getContentAsString(), ProjectResponse.class);
        UUID projectId = created.id();

        // 2. User A retrieves project -> 200 OK with ETag
        mockMvc.perform(get("/api/v1/projects/" + projectId)
                        .header(HttpHeaders.AUTHORIZATION, authA))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.ETAG, "\"0\""))
                .andExpect(jsonPath("$.id").value(projectId.toString()));

        // 3. User B attempts to retrieve User A's project -> 404 Not Found (tenant isolation)
        mockMvc.perform(get("/api/v1/projects/" + projectId)
                        .header(HttpHeaders.AUTHORIZATION, authB))
                .andExpect(status().isNotFound())
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.title").value("Resource Not Found"));

        // 4. User A updates project WITHOUT If-Match -> 428 Precondition Required
        ProjectUpdateRequest updateReq = new ProjectUpdateRequest("Kubernetes Engine v2", null, null);
        mockMvc.perform(patch("/api/v1/projects/" + projectId)
                        .header(HttpHeaders.AUTHORIZATION, authA)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(updateReq)))
                .andExpect(status().isPreconditionRequired())
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.title").value("Precondition Required"));

        // 5. User A updates project with STALE If-Match ("5") -> 412 Precondition Failed
        mockMvc.perform(patch("/api/v1/projects/" + projectId)
                        .header(HttpHeaders.AUTHORIZATION, authA)
                        .header(HttpHeaders.IF_MATCH, "\"5\"")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(updateReq)))
                .andExpect(status().isPreconditionFailed())
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.title").value("Precondition Failed"));

        // 6. User A updates project with MATCHING If-Match ("0") -> 200 OK with new ETag ("1")
        mockMvc.perform(patch("/api/v1/projects/" + projectId)
                        .header(HttpHeaders.AUTHORIZATION, authA)
                        .header(HttpHeaders.IF_MATCH, "\"0\"")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(updateReq)))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.ETAG, "\"1\""))
                .andExpect(jsonPath("$.name").value("Kubernetes Engine v2"))
                .andExpect(jsonPath("$.version").value(1));

        // 7. User B attempts to delete User A's project -> 404 Not Found
        mockMvc.perform(delete("/api/v1/projects/" + projectId)
                        .header(HttpHeaders.AUTHORIZATION, authB)
                        .header(HttpHeaders.IF_MATCH, "\"1\""))
                .andExpect(status().isNotFound());

        // 8. User A deletes project with matching If-Match ("1") -> 204 No Content
        mockMvc.perform(delete("/api/v1/projects/" + projectId)
                        .header(HttpHeaders.AUTHORIZATION, authA)
                        .header(HttpHeaders.IF_MATCH, "\"1\""))
                .andExpect(status().isNoContent());

        // 9. Verify project is gone -> 404 Not Found
        mockMvc.perform(get("/api/v1/projects/" + projectId)
                        .header(HttpHeaders.AUTHORIZATION, authA))
                .andExpect(status().isNotFound());
    }
}
