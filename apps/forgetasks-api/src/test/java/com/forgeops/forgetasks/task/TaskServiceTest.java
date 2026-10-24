package com.forgeops.forgetasks.task;

import com.forgeops.forgetasks.account.Account;
import com.forgeops.forgetasks.account.AccountRepository;
import com.forgeops.forgetasks.common.exception.PreconditionFailedException;
import com.forgeops.forgetasks.common.exception.PreconditionRequiredException;
import com.forgeops.forgetasks.common.exception.ResourceNotFoundException;
import com.forgeops.forgetasks.project.Project;
import com.forgeops.forgetasks.project.ProjectRepository;
import com.forgeops.forgetasks.task.dto.TaskCreateRequest;
import com.forgeops.forgetasks.task.dto.TaskResponse;
import com.forgeops.forgetasks.task.dto.TaskUpdateRequest;
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
class TaskServiceTest {

    @Mock
    private TaskRepository taskRepository;

    @Mock
    private ProjectRepository projectRepository;

    @Mock
    private AccountRepository accountRepository;

    private TaskService taskService;
    private Account owner;
    private Project project;

    @BeforeEach
    void setUp() {
        taskService = new TaskService(taskRepository, projectRepository, accountRepository);
        owner = new Account("alice", "hash", "ROLE_USER");
        owner.setId(UUID.randomUUID());

        project = new Project(owner, "P1", "Desc");
        project.setId(UUID.randomUUID());
    }

    @Test
    @DisplayName("createTask: successfully creates task under owner's project")
    void shouldCreateTask() {
        TaskCreateRequest request = new TaskCreateRequest("Write Unit Tests", "High coverage", TaskPriority.HIGH, null, null);

        when(accountRepository.findByUsername("alice")).thenReturn(Optional.of(owner));
        when(projectRepository.findByIdAndOwner(project.getId(), owner)).thenReturn(Optional.of(project));

        Task saved = new Task(project, "Write Unit Tests", "High coverage", TaskPriority.HIGH, null);
        saved.setId(UUID.randomUUID());
        when(taskRepository.save(any(Task.class))).thenReturn(saved);

        TaskResponse response = taskService.createTask(project.getId(), request, "alice");

        assertThat(response).isNotNull();
        assertThat(response.title()).isEqualTo("Write Unit Tests");
        assertThat(response.priority()).isEqualTo(TaskPriority.HIGH);
        assertThat(response.status()).isEqualTo(TaskStatus.TODO);
        verify(taskRepository).save(any(Task.class));
    }

    @Test
    @DisplayName("getTask: throws ResourceNotFoundException (404) on non-owned task")
    void shouldThrowNotFoundOnCrossTenantAccess() {
        UUID taskId = UUID.randomUUID();
        when(accountRepository.findByUsername("alice")).thenReturn(Optional.of(owner));
        when(taskRepository.findByIdAndOwner(taskId, owner)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> taskService.getTask(taskId, "alice"))
                .isInstanceOf(ResourceNotFoundException.class)
                .hasMessageContaining(taskId.toString());
    }

    @Test
    @DisplayName("listTasksForProject: throws 404 when project does not belong to owner")
    void shouldThrowNotFoundWhenListingTasksForNonOwnedProject() {
        UUID projectId = UUID.randomUUID();
        when(accountRepository.findByUsername("alice")).thenReturn(Optional.of(owner));
        when(projectRepository.existsByIdAndOwner(projectId, owner)).thenReturn(false);

        assertThatThrownBy(() -> taskService.listTasksForProject(projectId, "alice", null, null, PageRequest.of(0, 10)))
                .isInstanceOf(ResourceNotFoundException.class);
    }

    @Test
    @DisplayName("listTasksForProject: returns filtered tasks when project is owned")
    void shouldListTasksForOwnedProject() {
        when(accountRepository.findByUsername("alice")).thenReturn(Optional.of(owner));
        when(projectRepository.existsByIdAndOwner(project.getId(), owner)).thenReturn(true);

        Task t1 = new Task(project, "T1", "D1", TaskPriority.MEDIUM, null);
        t1.setId(UUID.randomUUID());
        when(taskRepository.findByProjectIdAndOwnerWithFilters(eq(project.getId()), eq(owner), eq(TaskStatus.TODO), isNull(), any()))
                .thenReturn(new PageImpl<>(List.of(t1)));

        Page<TaskResponse> result = taskService.listTasksForProject(project.getId(), "alice", TaskStatus.TODO, null, PageRequest.of(0, 10));

        assertThat(result.getContent()).hasSize(1);
        assertThat(result.getContent().get(0).title()).isEqualTo("T1");
    }

    @Test
    @DisplayName("updateTask: rejects missing If-Match (428) and stale If-Match (412)")
    void shouldEnforceIfMatchPreconditionsOnUpdate() {
        UUID taskId = UUID.randomUUID();
        Task existing = new Task(project, "T1", "D1", TaskPriority.LOW, null);
        existing.setId(taskId);
        existing.setVersion(5L);

        when(accountRepository.findByUsername("alice")).thenReturn(Optional.of(owner));
        when(taskRepository.findByIdAndOwner(taskId, owner)).thenReturn(Optional.of(existing));

        TaskUpdateRequest updateRequest = new TaskUpdateRequest("Updated", null, TaskStatus.IN_PROGRESS, null, null, null);

        // Missing
        assertThatThrownBy(() -> taskService.updateTask(taskId, "alice", updateRequest, null))
                .isInstanceOf(PreconditionRequiredException.class);

        // Stale
        assertThatThrownBy(() -> taskService.updateTask(taskId, "alice", updateRequest, 4L))
                .isInstanceOf(PreconditionFailedException.class);

        // Matching
        Task updated = new Task(project, "Updated", "D1", TaskPriority.LOW, null);
        updated.setId(taskId);
        updated.setStatus(TaskStatus.IN_PROGRESS);
        updated.setVersion(6L);
        when(taskRepository.saveAndFlush(any(Task.class))).thenReturn(updated);

        TaskResponse response = taskService.updateTask(taskId, "alice", updateRequest, 5L);
        assertThat(response.title()).isEqualTo("Updated");
        assertThat(response.status()).isEqualTo(TaskStatus.IN_PROGRESS);
        assertThat(response.version()).isEqualTo(6L);
    }

    @Test
    @DisplayName("deleteTask: enforces If-Match on deletion")
    void shouldEnforceIfMatchOnDelete() {
        UUID taskId = UUID.randomUUID();
        Task existing = new Task(project, "T1", "D1", TaskPriority.LOW, null);
        existing.setId(taskId);
        existing.setVersion(2L);

        when(accountRepository.findByUsername("alice")).thenReturn(Optional.of(owner));
        when(taskRepository.findByIdAndOwner(taskId, owner)).thenReturn(Optional.of(existing));

        assertThatThrownBy(() -> taskService.deleteTask(taskId, "alice", null))
                .isInstanceOf(PreconditionRequiredException.class);

        assertThatThrownBy(() -> taskService.deleteTask(taskId, "alice", 1L))
                .isInstanceOf(PreconditionFailedException.class);

        taskService.deleteTask(taskId, "alice", 2L);
        verify(taskRepository).delete(existing);
    }

    @Test
    @DisplayName("createTask: successfully assigns account when assignedAccountId provided")
    void shouldCreateTaskWithAssignedAccount() {
        UUID assignedId = UUID.randomUUID();
        Account assigned = new Account("bob", "hash", "ROLE_USER");
        assigned.setId(assignedId);

        TaskCreateRequest request = new TaskCreateRequest("Assigned Task", "Desc", TaskPriority.LOW, assignedId, Instant.now());

        when(accountRepository.findByUsername("alice")).thenReturn(Optional.of(owner));
        when(projectRepository.findByIdAndOwner(project.getId(), owner)).thenReturn(Optional.of(project));
        when(accountRepository.findById(assignedId)).thenReturn(Optional.of(assigned));

        Task saved = new Task(project, "Assigned Task", "Desc", TaskPriority.LOW, null);
        saved.setId(UUID.randomUUID());
        saved.setAssignedAccount(assigned);
        when(taskRepository.save(any(Task.class))).thenReturn(saved);

        TaskResponse response = taskService.createTask(project.getId(), request, "alice");
        assertThat(response.assignedAccountId()).isEqualTo(assignedId);
    }

    @Test
    @DisplayName("updateTask: updates assigned account, priority, and due date")
    void shouldUpdateTaskWithAssignedAccountAndDueDate() {
        UUID taskId = UUID.randomUUID();
        UUID assignedId = UUID.randomUUID();
        Account assigned = new Account("bob", "hash", "ROLE_USER");
        assigned.setId(assignedId);

        Task existing = new Task(project, "T1", "D1", TaskPriority.LOW, null);
        existing.setId(taskId);
        existing.setVersion(1L);

        when(accountRepository.findByUsername("alice")).thenReturn(Optional.of(owner));
        when(taskRepository.findByIdAndOwner(taskId, owner)).thenReturn(Optional.of(existing));
        when(accountRepository.findById(assignedId)).thenReturn(Optional.of(assigned));

        Instant due = Instant.now().plusSeconds(7200);
        TaskUpdateRequest updateReq = new TaskUpdateRequest(
                "T1 Updated", "New Desc", TaskStatus.BLOCKED, TaskPriority.HIGH, assignedId, due
        );

        Task updated = new Task(project, "T1 Updated", "New Desc", TaskPriority.HIGH, due);
        updated.setId(taskId);
        updated.setAssignedAccount(assigned);
        updated.setStatus(TaskStatus.BLOCKED);
        updated.setVersion(2L);
        when(taskRepository.saveAndFlush(any(Task.class))).thenReturn(updated);

        TaskResponse response = taskService.updateTask(taskId, "alice", updateReq, 1L);
        assertThat(response.assignedAccountId()).isEqualTo(assignedId);
        assertThat(response.priority()).isEqualTo(TaskPriority.HIGH);
        assertThat(response.status()).isEqualTo(TaskStatus.BLOCKED);
    }
}
