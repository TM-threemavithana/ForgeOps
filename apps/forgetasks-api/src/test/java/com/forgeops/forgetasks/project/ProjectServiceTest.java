package com.forgeops.forgetasks.project;

import com.forgeops.forgetasks.account.Account;
import com.forgeops.forgetasks.account.AccountRepository;
import com.forgeops.forgetasks.common.exception.PreconditionFailedException;
import com.forgeops.forgetasks.common.exception.PreconditionRequiredException;
import com.forgeops.forgetasks.common.exception.ResourceNotFoundException;
import com.forgeops.forgetasks.project.dto.ProjectCreateRequest;
import com.forgeops.forgetasks.project.dto.ProjectResponse;
import com.forgeops.forgetasks.project.dto.ProjectUpdateRequest;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ProjectServiceTest {

    @Mock
    private ProjectRepository projectRepository;

    @Mock
    private AccountRepository accountRepository;

    private ProjectService projectService;
    private Account owner;

    @BeforeEach
    void setUp() {
        projectService = new ProjectService(projectRepository, accountRepository);
        owner = new Account("alice", "hash", "ROLE_USER");
        owner.setId(UUID.randomUUID());
    }

    @Test
    @DisplayName("createProject: successfully creates project with initial version 0")
    void shouldCreateProject() {
        ProjectCreateRequest request = new ProjectCreateRequest("Cloud Migration", "Kubernetes rollout");
        when(accountRepository.findByUsername("alice")).thenReturn(Optional.of(owner));

        Project saved = new Project(owner, "Cloud Migration", "Kubernetes rollout");
        saved.setId(UUID.randomUUID());
        saved.setVersion(0L);
        when(projectRepository.save(any(Project.class))).thenReturn(saved);

        ProjectResponse response = projectService.createProject(request, "alice");

        assertThat(response).isNotNull();
        assertThat(response.name()).isEqualTo("Cloud Migration");
        assertThat(response.version()).isEqualTo(0L);
        verify(projectRepository).save(any(Project.class));
    }

    @Test
    @DisplayName("getProject: throws ResourceNotFoundException (404) on non-owned or non-existent project")
    void shouldThrowNotFoundOnCrossTenantAccess() {
        UUID projectId = UUID.randomUUID();
        when(accountRepository.findByUsername("alice")).thenReturn(Optional.of(owner));
        when(projectRepository.findByIdAndOwner(projectId, owner)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> projectService.getProject(projectId, "alice"))
                .isInstanceOf(ResourceNotFoundException.class)
                .hasMessageContaining(projectId.toString());
    }

    @Test
    @DisplayName("listProjects: returns paged projects for owner")
    void shouldListProjects() {
        when(accountRepository.findByUsername("alice")).thenReturn(Optional.of(owner));
        Project p1 = new Project(owner, "P1", "Desc");
        p1.setId(UUID.randomUUID());
        when(projectRepository.findByOwnerAndArchivedAtIsNull(eq(owner), any())).thenReturn(new PageImpl<>(List.of(p1)));

        Page<ProjectResponse> result = projectService.listProjects("alice", false, PageRequest.of(0, 10));

        assertThat(result.getContent()).hasSize(1);
        assertThat(result.getContent().get(0).name()).isEqualTo("P1");
    }

    @Test
    @DisplayName("updateProject: throws PreconditionRequiredException (428) when If-Match is missing")
    void shouldRequireIfMatchForUpdate() {
        UUID projectId = UUID.randomUUID();
        Project existing = new Project(owner, "P1", "Desc");
        existing.setId(projectId);
        existing.setVersion(2L);

        when(accountRepository.findByUsername("alice")).thenReturn(Optional.of(owner));
        when(projectRepository.findByIdAndOwner(projectId, owner)).thenReturn(Optional.of(existing));

        ProjectUpdateRequest updateRequest = new ProjectUpdateRequest("New Name", null, null);

        assertThatThrownBy(() -> projectService.updateProject(projectId, "alice", updateRequest, null))
                .isInstanceOf(PreconditionRequiredException.class)
                .hasMessageContaining("If-Match");

        verify(projectRepository, never()).saveAndFlush(any());
    }

    @Test
    @DisplayName("updateProject: throws PreconditionFailedException (412) when If-Match version is stale")
    void shouldRejectStaleIfMatchForUpdate() {
        UUID projectId = UUID.randomUUID();
        Project existing = new Project(owner, "P1", "Desc");
        existing.setId(projectId);
        existing.setVersion(2L);

        when(accountRepository.findByUsername("alice")).thenReturn(Optional.of(owner));
        when(projectRepository.findByIdAndOwner(projectId, owner)).thenReturn(Optional.of(existing));

        ProjectUpdateRequest updateRequest = new ProjectUpdateRequest("New Name", null, null);

        assertThatThrownBy(() -> projectService.updateProject(projectId, "alice", updateRequest, 1L))
                .isInstanceOf(PreconditionFailedException.class)
                .hasMessageContaining("does not match");

        verify(projectRepository, never()).saveAndFlush(any());
    }

    @Test
    @DisplayName("updateProject: updates fields and archives project when matching If-Match provided")
    void shouldUpdateProjectWithMatchingIfMatch() {
        UUID projectId = UUID.randomUUID();
        Project existing = new Project(owner, "P1", "Desc");
        existing.setId(projectId);
        existing.setVersion(1L);

        when(accountRepository.findByUsername("alice")).thenReturn(Optional.of(owner));
        when(projectRepository.findByIdAndOwner(projectId, owner)).thenReturn(Optional.of(existing));

        Project updated = new Project(owner, "Updated Name", "Updated Desc");
        updated.setId(projectId);
        updated.setVersion(2L);
        when(projectRepository.saveAndFlush(any(Project.class))).thenReturn(updated);

        ProjectUpdateRequest updateRequest = new ProjectUpdateRequest("Updated Name", "Updated Desc", true);
        ProjectResponse response = projectService.updateProject(projectId, "alice", updateRequest, 1L);

        assertThat(response.name()).isEqualTo("Updated Name");
        assertThat(response.version()).isEqualTo(2L);
        verify(projectRepository).saveAndFlush(existing);
    }

    @Test
    @DisplayName("deleteProject: enforces If-Match presence and version match")
    void shouldEnforceIfMatchOnDelete() {
        UUID projectId = UUID.randomUUID();
        Project existing = new Project(owner, "P1", "Desc");
        existing.setId(projectId);
        existing.setVersion(3L);

        when(accountRepository.findByUsername("alice")).thenReturn(Optional.of(owner));
        when(projectRepository.findByIdAndOwner(projectId, owner)).thenReturn(Optional.of(existing));

        assertThatThrownBy(() -> projectService.deleteProject(projectId, "alice", null))
                .isInstanceOf(PreconditionRequiredException.class);

        assertThatThrownBy(() -> projectService.deleteProject(projectId, "alice", 2L))
                .isInstanceOf(PreconditionFailedException.class);

        projectService.deleteProject(projectId, "alice", 3L);
        verify(projectRepository).delete(existing);
    }

    @Test
    @DisplayName("updateProject: unarchives project when archived=false and handles null/blank fields")
    void shouldUnarchiveProjectAndHandleBlankFields() {
        UUID projectId = UUID.randomUUID();
        Project existing = new Project(owner, "P1", "Desc");
        existing.setId(projectId);
        existing.setVersion(1L);
        existing.setArchivedAt(Instant.now());

        when(accountRepository.findByUsername("alice")).thenReturn(Optional.of(owner));
        when(projectRepository.findByIdAndOwner(projectId, owner)).thenReturn(Optional.of(existing));

        Project updated = new Project(owner, "P1", null);
        updated.setId(projectId);
        updated.setVersion(2L);
        updated.setArchivedAt(null);
        when(projectRepository.saveAndFlush(any(Project.class))).thenReturn(updated);

        ProjectUpdateRequest updateRequest = new ProjectUpdateRequest("", null, false);
        ProjectResponse response = projectService.updateProject(projectId, "alice", updateRequest, 1L);

        assertThat(response.archivedAt()).isNull();
        assertThat(existing.getArchivedAt()).isNull();
    }

    @Test
    @DisplayName("getProjectEntity: returns internal entity or throws 404")
    void shouldGetProjectEntity() {
        UUID projectId = UUID.randomUUID();
        Project existing = new Project(owner, "P1", "Desc");
        existing.setId(projectId);

        when(projectRepository.findByIdAndOwner(projectId, owner)).thenReturn(Optional.of(existing));
        assertThat(projectService.getProjectEntity(projectId, owner)).isEqualTo(existing);

        when(projectRepository.findByIdAndOwner(projectId, owner)).thenReturn(Optional.empty());
        assertThatThrownBy(() -> projectService.getProjectEntity(projectId, owner))
                .isInstanceOf(ResourceNotFoundException.class);
    }
}
