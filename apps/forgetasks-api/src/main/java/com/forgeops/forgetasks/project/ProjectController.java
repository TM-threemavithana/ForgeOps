package com.forgeops.forgetasks.project;

import com.forgeops.forgetasks.common.util.ETagUtils;
import com.forgeops.forgetasks.project.dto.ProjectCreateRequest;
import com.forgeops.forgetasks.project.dto.ProjectResponse;
import com.forgeops.forgetasks.project.dto.ProjectUpdateRequest;
import com.forgeops.forgetasks.security.SecurityUtils;
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
@RequestMapping("/api/v1/projects")
public class ProjectController {

    private final ProjectService projectService;

    public ProjectController(ProjectService projectService) {
        this.projectService = projectService;
    }

    private String getCurrentUsername() {
        return SecurityUtils.getCurrentUsername()
                .orElseThrow(() -> new AccessDeniedException("User is not authenticated"));
    }

    @PostMapping
    public ResponseEntity<ProjectResponse> createProject(@Valid @RequestBody ProjectCreateRequest request) {
        String username = getCurrentUsername();
        ProjectResponse response = projectService.createProject(request, username);

        URI location = ServletUriComponentsBuilder.fromCurrentRequest()
                .path("/{id}")
                .buildAndExpand(response.id())
                .toUri();

        return ResponseEntity.created(location)
                .eTag(ETagUtils.formatETag(response.version()))
                .body(response);
    }

    @GetMapping("/{id}")
    public ResponseEntity<ProjectResponse> getProject(@PathVariable UUID id) {
        String username = getCurrentUsername();
        ProjectResponse response = projectService.getProject(id, username);

        return ResponseEntity.ok()
                .eTag(ETagUtils.formatETag(response.version()))
                .body(response);
    }

    @GetMapping
    public ResponseEntity<Page<ProjectResponse>> listProjects(
            @RequestParam(required = false, defaultValue = "false") boolean includeArchived,
            @PageableDefault(size = 20) Pageable pageable) {

        String username = getCurrentUsername();
        Page<ProjectResponse> response = projectService.listProjects(username, includeArchived, pageable);
        return ResponseEntity.ok(response);
    }

    @PatchMapping("/{id}")
    public ResponseEntity<ProjectResponse> updateProject(
            @PathVariable UUID id,
            @RequestHeader(value = HttpHeaders.IF_MATCH, required = false) String ifMatch,
            @Valid @RequestBody ProjectUpdateRequest request) {

        String username = getCurrentUsername();
        Long version = ETagUtils.parseIfMatch(ifMatch);
        ProjectResponse response = projectService.updateProject(id, username, request, version);

        return ResponseEntity.ok()
                .eTag(ETagUtils.formatETag(response.version()))
                .body(response);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> deleteProject(
            @PathVariable UUID id,
            @RequestHeader(value = HttpHeaders.IF_MATCH, required = false) String ifMatch) {

        String username = getCurrentUsername();
        Long version = ETagUtils.parseIfMatch(ifMatch);
        projectService.deleteProject(id, username, version);

        return ResponseEntity.noContent().build();
    }
}
