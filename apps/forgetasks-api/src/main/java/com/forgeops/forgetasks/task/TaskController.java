package com.forgeops.forgetasks.task;

import com.forgeops.forgetasks.common.util.ETagUtils;
import com.forgeops.forgetasks.security.SecurityUtils;
import com.forgeops.forgetasks.task.dto.TaskCreateRequest;
import com.forgeops.forgetasks.task.dto.TaskResponse;
import com.forgeops.forgetasks.task.dto.TaskUpdateRequest;
import jakarta.validation.Valid;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.web.PageableDefault;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import java.net.URI;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1")
public class TaskController {

    private final TaskService taskService;

    public TaskController(TaskService taskService) {
        this.taskService = taskService;
    }

    private String getCurrentUsername() {
        return SecurityUtils.getCurrentUsername()
                .orElseThrow(() -> new AccessDeniedException("User is not authenticated"));
    }

    @PostMapping("/projects/{projectId}/tasks")
    public ResponseEntity<TaskResponse> createTask(
            @PathVariable UUID projectId,
            @Valid @RequestBody TaskCreateRequest request) {

        String username = getCurrentUsername();
        TaskResponse response = taskService.createTask(projectId, request, username);

        URI location = ServletUriComponentsBuilder.fromCurrentContextPath()
                .path("/api/v1/tasks/{id}")
                .buildAndExpand(response.id())
                .toUri();

        return ResponseEntity.created(location)
                .eTag(ETagUtils.formatETag(response.version()))
                .body(response);
    }

    @GetMapping("/projects/{projectId}/tasks")
    public ResponseEntity<Page<TaskResponse>> listTasksForProject(
            @PathVariable UUID projectId,
            @RequestParam(required = false) TaskStatus status,
            @RequestParam(required = false) TaskPriority priority,
            @PageableDefault(size = 20) Pageable pageable) {

        String username = getCurrentUsername();
        Page<TaskResponse> response = taskService.listTasksForProject(projectId, username, status, priority, pageable);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/tasks/{id}")
    public ResponseEntity<TaskResponse> getTask(@PathVariable UUID id) {
        String username = getCurrentUsername();
        TaskResponse response = taskService.getTask(id, username);

        return ResponseEntity.ok()
                .eTag(ETagUtils.formatETag(response.version()))
                .body(response);
    }

    @PatchMapping("/tasks/{id}")
    public ResponseEntity<TaskResponse> updateTask(
            @PathVariable UUID id,
            @RequestHeader(value = HttpHeaders.IF_MATCH, required = false) String ifMatch,
            @Valid @RequestBody TaskUpdateRequest request) {

        String username = getCurrentUsername();
        Long version = ETagUtils.parseIfMatch(ifMatch);
        TaskResponse response = taskService.updateTask(id, username, request, version);

        return ResponseEntity.ok()
                .eTag(ETagUtils.formatETag(response.version()))
                .body(response);
    }

    @DeleteMapping("/tasks/{id}")
    public ResponseEntity<Void> deleteTask(
            @PathVariable UUID id,
            @RequestHeader(value = HttpHeaders.IF_MATCH, required = false) String ifMatch) {

        String username = getCurrentUsername();
        Long version = ETagUtils.parseIfMatch(ifMatch);
        taskService.deleteTask(id, username, version);

        return ResponseEntity.noContent().build();
    }
}
