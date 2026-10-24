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
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

@Service
public class TaskService {

    private final TaskRepository taskRepository;
    private final ProjectRepository projectRepository;
    private final AccountRepository accountRepository;

    public TaskService(TaskRepository taskRepository, ProjectRepository projectRepository, AccountRepository accountRepository) {
        this.taskRepository = taskRepository;
        this.projectRepository = projectRepository;
        this.accountRepository = accountRepository;
    }

    private Account getAuthenticatedAccount(String username) {
        return accountRepository.findByUsername(username)
                .orElseThrow(() -> new ResourceNotFoundException("Account not found: " + username));
    }

    @Transactional
    public TaskResponse createTask(UUID projectId, TaskCreateRequest request, String username) {
        Account owner = getAuthenticatedAccount(username);
        Project project = projectRepository.findByIdAndOwner(projectId, owner)
                .orElseThrow(() -> new ResourceNotFoundException("Project not found with id: " + projectId));

        Task task = new Task(project, request.title(), request.description(), request.priority(), request.dueDate());

        if (request.assignedAccountId() != null) {
            Account assigned = accountRepository.findById(request.assignedAccountId())
                    .orElseThrow(() -> new ResourceNotFoundException("Assigned account not found with id: " + request.assignedAccountId()));
            task.setAssignedAccount(assigned);
        }

        Task saved = taskRepository.save(task);
        return TaskResponse.from(saved);
    }

    @Transactional(readOnly = true)
    public TaskResponse getTask(UUID taskId, String username) {
        Account owner = getAuthenticatedAccount(username);
        Task task = taskRepository.findByIdAndOwner(taskId, owner)
                .orElseThrow(() -> new ResourceNotFoundException("Task not found with id: " + taskId));
        return TaskResponse.from(task);
    }

    @Transactional(readOnly = true)
    public Page<TaskResponse> listTasksForProject(UUID projectId, String username, TaskStatus status, TaskPriority priority, Pageable pageable) {
        Account owner = getAuthenticatedAccount(username);
        if (!projectRepository.existsByIdAndOwner(projectId, owner)) {
            throw new ResourceNotFoundException("Project not found with id: " + projectId);
        }

        Page<Task> tasks = taskRepository.findByProjectIdAndOwnerWithFilters(projectId, owner, status, priority, pageable);
        return tasks.map(TaskResponse::from);
    }

    @Transactional
    public TaskResponse updateTask(UUID taskId, String username, TaskUpdateRequest request, Long ifMatchVersion) {
        Account owner = getAuthenticatedAccount(username);
        Task task = taskRepository.findByIdAndOwner(taskId, owner)
                .orElseThrow(() -> new ResourceNotFoundException("Task not found with id: " + taskId));

        if (ifMatchVersion == null) {
            throw new PreconditionRequiredException("Header 'If-Match' is required for mutating task updates.");
        }

        if (!task.getVersion().equals(ifMatchVersion)) {
            throw new PreconditionFailedException("Supplied If-Match version " + ifMatchVersion +
                    " does not match current resource version " + task.getVersion() + ".");
        }

        if (request.title() != null && !request.title().isBlank()) {
            task.setTitle(request.title());
        }
        if (request.description() != null) {
            task.setDescription(request.description());
        }
        if (request.status() != null) {
            task.setStatus(request.status());
        }
        if (request.priority() != null) {
            task.setPriority(request.priority());
        }
        if (request.dueDate() != null) {
            task.setDueDate(request.dueDate());
        }
        if (request.assignedAccountId() != null) {
            Account assigned = accountRepository.findById(request.assignedAccountId())
                    .orElseThrow(() -> new ResourceNotFoundException("Assigned account not found with id: " + request.assignedAccountId()));
            task.setAssignedAccount(assigned);
        }

        Task updated = taskRepository.saveAndFlush(task);
        return TaskResponse.from(updated);
    }

    @Transactional
    public void deleteTask(UUID taskId, String username, Long ifMatchVersion) {
        Account owner = getAuthenticatedAccount(username);
        Task task = taskRepository.findByIdAndOwner(taskId, owner)
                .orElseThrow(() -> new ResourceNotFoundException("Task not found with id: " + taskId));

        if (ifMatchVersion == null) {
            throw new PreconditionRequiredException("Header 'If-Match' is required for task deletion.");
        }

        if (!task.getVersion().equals(ifMatchVersion)) {
            throw new PreconditionFailedException("Supplied If-Match version " + ifMatchVersion +
                    " does not match current resource version " + task.getVersion() + ".");
        }

        taskRepository.delete(task);
    }
}
