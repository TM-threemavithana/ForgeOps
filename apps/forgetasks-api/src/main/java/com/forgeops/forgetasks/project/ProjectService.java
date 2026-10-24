package com.forgeops.forgetasks.project;

import com.forgeops.forgetasks.account.Account;
import com.forgeops.forgetasks.account.AccountRepository;
import com.forgeops.forgetasks.common.exception.PreconditionFailedException;
import com.forgeops.forgetasks.common.exception.PreconditionRequiredException;
import com.forgeops.forgetasks.common.exception.ResourceNotFoundException;
import com.forgeops.forgetasks.project.dto.ProjectCreateRequest;
import com.forgeops.forgetasks.project.dto.ProjectResponse;
import com.forgeops.forgetasks.project.dto.ProjectUpdateRequest;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.UUID;

@Service
public class ProjectService {

    private final ProjectRepository projectRepository;
    private final AccountRepository accountRepository;

    public ProjectService(ProjectRepository projectRepository, AccountRepository accountRepository) {
        this.projectRepository = projectRepository;
        this.accountRepository = accountRepository;
    }

    private Account getAuthenticatedAccount(String username) {
        return accountRepository.findByUsername(username)
                .orElseThrow(() -> new ResourceNotFoundException("Account not found: " + username));
    }

    @Transactional
    public ProjectResponse createProject(ProjectCreateRequest request, String username) {
        Account owner = getAuthenticatedAccount(username);
        Project project = new Project(owner, request.name(), request.description());
        Project saved = projectRepository.save(project);
        return ProjectResponse.from(saved);
    }

    @Transactional(readOnly = true)
    public ProjectResponse getProject(UUID projectId, String username) {
        Account owner = getAuthenticatedAccount(username);
        Project project = projectRepository.findByIdAndOwner(projectId, owner)
                .orElseThrow(() -> new ResourceNotFoundException("Project not found with id: " + projectId));
        return ProjectResponse.from(project);
    }

    @Transactional(readOnly = true)
    public Page<ProjectResponse> listProjects(String username, boolean includeArchived, Pageable pageable) {
        Account owner = getAuthenticatedAccount(username);
        Page<Project> projects = includeArchived
                ? projectRepository.findByOwner(owner, pageable)
                : projectRepository.findByOwnerAndArchivedAtIsNull(owner, pageable);

        return projects.map(ProjectResponse::from);
    }

    @Transactional
    public ProjectResponse updateProject(UUID projectId, String username, ProjectUpdateRequest request, Long ifMatchVersion) {
        Account owner = getAuthenticatedAccount(username);
        Project project = projectRepository.findByIdAndOwner(projectId, owner)
                .orElseThrow(() -> new ResourceNotFoundException("Project not found with id: " + projectId));

        if (ifMatchVersion == null) {
            throw new PreconditionRequiredException("Header 'If-Match' is required for mutating project updates.");
        }

        if (!project.getVersion().equals(ifMatchVersion)) {
            throw new PreconditionFailedException("Supplied If-Match version " + ifMatchVersion +
                    " does not match current resource version " + project.getVersion() + ".");
        }

        if (request.name() != null && !request.name().isBlank()) {
            project.setName(request.name());
        }
        if (request.description() != null) {
            project.setDescription(request.description());
        }
        if (request.archived() != null) {
            if (request.archived() && project.getArchivedAt() == null) {
                project.setArchivedAt(Instant.now());
            } else if (!request.archived()) {
                project.setArchivedAt(null);
            }
        }

        Project updated = projectRepository.saveAndFlush(project);
        return ProjectResponse.from(updated);
    }

    @Transactional
    public void deleteProject(UUID projectId, String username, Long ifMatchVersion) {
        Account owner = getAuthenticatedAccount(username);
        Project project = projectRepository.findByIdAndOwner(projectId, owner)
                .orElseThrow(() -> new ResourceNotFoundException("Project not found with id: " + projectId));

        if (ifMatchVersion == null) {
            throw new PreconditionRequiredException("Header 'If-Match' is required for project deletion.");
        }

        if (!project.getVersion().equals(ifMatchVersion)) {
            throw new PreconditionFailedException("Supplied If-Match version " + ifMatchVersion +
                    " does not match current resource version " + project.getVersion() + ".");
        }

        projectRepository.delete(project);
    }

    @Transactional(readOnly = true)
    public Project getProjectEntity(UUID projectId, Account owner) {
        return projectRepository.findByIdAndOwner(projectId, owner)
                .orElseThrow(() -> new ResourceNotFoundException("Project not found with id: " + projectId));
    }
}
