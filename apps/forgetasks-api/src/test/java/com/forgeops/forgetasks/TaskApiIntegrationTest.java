package com.forgeops.forgetasks;

import com.forgeops.forgetasks.account.dto.AccountRegistrationRequest;
import com.forgeops.forgetasks.project.dto.ProjectCreateRequest;
import com.forgeops.forgetasks.project.dto.ProjectResponse;
import com.forgeops.forgetasks.task.TaskPriority;
import com.forgeops.forgetasks.task.TaskStatus;
import com.forgeops.forgetasks.task.dto.TaskCreateRequest;
import com.forgeops.forgetasks.task.dto.TaskResponse;
import com.forgeops.forgetasks.task.dto.TaskUpdateRequest;
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

class TaskApiIntegrationTest extends AbstractIntegrationTest {

    private String userA;
    private String userB;
    private final String password = "Password1234!";

    @BeforeEach
    void setUpUsers() throws Exception {
        userA = "task_user_a_" + UUID.randomUUID().toString().substring(0, 8);
        userB = "task_user_b_" + UUID.randomUUID().toString().substring(0, 8);

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
    @DisplayName("Task API: Creation, listing, filtering, strong ETag, If-Match, and cross-user isolation")
    void shouldPerformFullTaskLifecycle() throws Exception {
        String authA = basicAuthHeader(userA, password);
        String authB = basicAuthHeader(userB, password);

        // 1. User A creates project
        MvcResult projectRes = mockMvc.perform(post("/api/v1/projects")
                        .header(HttpHeaders.AUTHORIZATION, authA)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new ProjectCreateRequest("Infra Lab", "Lab description"))))
                .andExpect(status().isCreated())
                .andReturn();

        ProjectResponse project = objectMapper.readValue(projectRes.getResponse().getContentAsString(), ProjectResponse.class);
        UUID projectId = project.id();

        // 2. User A creates task
        TaskCreateRequest taskReq = new TaskCreateRequest(
                "Configure PostgreSQL", "Deploy PG 16 with Flyway", TaskPriority.HIGH, null, null
        );
        MvcResult taskRes = mockMvc.perform(post("/api/v1/projects/" + projectId + "/tasks")
                        .header(HttpHeaders.AUTHORIZATION, authA)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(taskReq)))
                .andExpect(status().isCreated())
                .andExpect(header().string(HttpHeaders.ETAG, "\"0\""))
                .andExpect(jsonPath("$.status").value("TODO"))
                .andExpect(jsonPath("$.priority").value("HIGH"))
                .andReturn();

        TaskResponse task = objectMapper.readValue(taskRes.getResponse().getContentAsString(), TaskResponse.class);
        UUID taskId = task.id();

        // 3. User B attempts to access task -> 404 Not Found
        mockMvc.perform(get("/api/v1/tasks/" + taskId)
                        .header(HttpHeaders.AUTHORIZATION, authB))
                .andExpect(status().isNotFound());

        // 4. User B attempts to list tasks of User A's project -> 404 Not Found
        mockMvc.perform(get("/api/v1/projects/" + projectId + "/tasks")
                        .header(HttpHeaders.AUTHORIZATION, authB))
                .andExpect(status().isNotFound());

        // 5. User A lists tasks with filters -> 200 OK
        mockMvc.perform(get("/api/v1/projects/" + projectId + "/tasks?status=TODO&priority=HIGH")
                        .header(HttpHeaders.AUTHORIZATION, authA))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content[0].title").value("Configure PostgreSQL"));

        // 6. User A updates task without If-Match -> 428 Precondition Required
        TaskUpdateRequest updateReq = new TaskUpdateRequest(
                "Configure PostgreSQL 16", null, TaskStatus.IN_PROGRESS, null, null, null
        );
        mockMvc.perform(patch("/api/v1/tasks/" + taskId)
                        .header(HttpHeaders.AUTHORIZATION, authA)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(updateReq)))
                .andExpect(status().isPreconditionRequired());

        // 7. User A updates task with matching If-Match ("0") -> 200 OK with ETag ("1")
        mockMvc.perform(patch("/api/v1/tasks/" + taskId)
                        .header(HttpHeaders.AUTHORIZATION, authA)
                        .header(HttpHeaders.IF_MATCH, "\"0\"")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(updateReq)))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.ETAG, "\"1\""))
                .andExpect(jsonPath("$.status").value("IN_PROGRESS"))
                .andExpect(jsonPath("$.version").value(1));

        // 8. User A deletes task with matching If-Match ("1") -> 204 No Content
        mockMvc.perform(delete("/api/v1/tasks/" + taskId)
                        .header(HttpHeaders.AUTHORIZATION, authA)
                        .header(HttpHeaders.IF_MATCH, "\"1\""))
                .andExpect(status().isNoContent());

        // 9. Verify task is deleted -> 404 Not Found
        mockMvc.perform(get("/api/v1/tasks/" + taskId)
                        .header(HttpHeaders.AUTHORIZATION, authA))
                .andExpect(status().isNotFound());
    }
}
