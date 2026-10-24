package com.forgeops.forgetasks;

import com.forgeops.forgetasks.account.Account;
import com.forgeops.forgetasks.account.AccountRole;
import com.forgeops.forgetasks.common.exception.GlobalExceptionHandler;
import com.forgeops.forgetasks.common.util.ETagUtils;
import com.forgeops.forgetasks.project.Project;
import com.forgeops.forgetasks.security.SecurityUtils;
import com.forgeops.forgetasks.task.Task;
import com.forgeops.forgetasks.task.TaskPriority;
import com.forgeops.forgetasks.task.TaskStatus;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.userdetails.User;

import java.time.Instant;
import java.util.Collections;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class DomainAndSecurityCoverageTest {

    @Test
    @DisplayName("Account domain model: test getters, setters, equals and hashCode")
    void shouldTestAccountModel() {
        Account a1 = new Account();
        UUID id1 = UUID.randomUUID();
        a1.setId(id1);
        a1.setUsername("user1");
        a1.setPasswordHash("hash1");
        a1.setRole("ROLE_ADMIN");
        Instant now = Instant.now();
        a1.setCreatedAt(now);

        assertThat(a1.getId()).isEqualTo(id1);
        assertThat(a1.getUsername()).isEqualTo("user1");
        assertThat(a1.getPasswordHash()).isEqualTo("hash1");
        assertThat(a1.getRole()).isEqualTo("ROLE_ADMIN");
        assertThat(a1.getCreatedAt()).isEqualTo(now);

        Account a2 = new Account("user1", "hash1", null);
        a2.setId(id1);

        assertThat(a1).isEqualTo(a1);
        assertThat(a1).isEqualTo(a2);
        assertThat(a1).isNotEqualTo(null);
        assertThat(a1).isNotEqualTo(new Object());
        assertThat(a1.hashCode()).isEqualTo(a2.hashCode());

        Account a3 = new Account("user3", "hash3", "ROLE_USER");
        a3.setId(UUID.randomUUID());
        assertThat(a1).isNotEqualTo(a3);

        assertThat(AccountRole.valueOf("ROLE_USER")).isEqualTo(AccountRole.ROLE_USER);
        assertThat(AccountRole.values()).hasSize(2);
    }

    @Test
    @DisplayName("Project domain model: test getters, setters, preUpdate, equals and hashCode")
    void shouldTestProjectModel() {
        Account owner = new Account("owner", "hash", "ROLE_USER");
        owner.setId(UUID.randomUUID());

        Project p1 = new Project();
        UUID pId = UUID.randomUUID();
        p1.setId(pId);
        p1.setOwner(owner);
        p1.setName("Proj 1");
        p1.setDescription("Desc 1");
        p1.setVersion(1L);
        Instant now = Instant.now();
        p1.setCreatedAt(now);
        p1.setUpdatedAt(now);
        p1.setArchivedAt(now);
        p1.preUpdate();

        assertThat(p1.getId()).isEqualTo(pId);
        assertThat(p1.getOwner()).isEqualTo(owner);
        assertThat(p1.getName()).isEqualTo("Proj 1");
        assertThat(p1.getDescription()).isEqualTo("Desc 1");
        assertThat(p1.getVersion()).isEqualTo(1L);
        assertThat(p1.getCreatedAt()).isEqualTo(now);
        assertThat(p1.getUpdatedAt()).isNotNull();
        assertThat(p1.getArchivedAt()).isEqualTo(now);

        Project p2 = new Project(owner, "Proj 1", "Desc 1");
        p2.setId(pId);

        assertThat(p1).isEqualTo(p1);
        assertThat(p1).isEqualTo(p2);
        assertThat(p1).isNotEqualTo(null);
        assertThat(p1).isNotEqualTo(new Object());
        assertThat(p1.hashCode()).isEqualTo(p2.hashCode());

        Project p3 = new Project(owner, "Proj 3", "Desc 3");
        p3.setId(UUID.randomUUID());
        assertThat(p1).isNotEqualTo(p3);
    }

    @Test
    @DisplayName("Task domain model: test getters, setters, preUpdate, equals and hashCode")
    void shouldTestTaskModel() {
        Account owner = new Account("owner", "hash", "ROLE_USER");
        owner.setId(UUID.randomUUID());
        Project project = new Project(owner, "P", "D");
        project.setId(UUID.randomUUID());

        Task t1 = new Task();
        UUID tId = UUID.randomUUID();
        t1.setId(tId);
        t1.setProject(project);
        t1.setAssignedAccount(owner);
        t1.setTitle("Task 1");
        t1.setDescription("Task Desc");
        t1.setStatus(TaskStatus.DONE);
        t1.setPriority(TaskPriority.HIGH);
        Instant due = Instant.now().plusSeconds(3600);
        t1.setDueDate(due);
        t1.setVersion(3L);
        Instant now = Instant.now();
        t1.setCreatedAt(now);
        t1.setUpdatedAt(now);
        t1.preUpdate();

        assertThat(t1.getId()).isEqualTo(tId);
        assertThat(t1.getProject()).isEqualTo(project);
        assertThat(t1.getAssignedAccount()).isEqualTo(owner);
        assertThat(t1.getTitle()).isEqualTo("Task 1");
        assertThat(t1.getDescription()).isEqualTo("Task Desc");
        assertThat(t1.getStatus()).isEqualTo(TaskStatus.DONE);
        assertThat(t1.getPriority()).isEqualTo(TaskPriority.HIGH);
        assertThat(t1.getDueDate()).isEqualTo(due);
        assertThat(t1.getVersion()).isEqualTo(3L);
        assertThat(t1.getCreatedAt()).isEqualTo(now);
        assertThat(t1.getUpdatedAt()).isNotNull();

        Task t2 = new Task(project, "Task 1", "Task Desc", TaskPriority.HIGH, due);
        t2.setId(tId);

        assertThat(t1).isEqualTo(t1);
        assertThat(t1).isEqualTo(t2);
        assertThat(t1).isNotEqualTo(null);
        assertThat(t1).isNotEqualTo(new Object());
        assertThat(t1.hashCode()).isEqualTo(t2.hashCode());

        Task t3 = new Task(project, "Task 3", null, null, null);
        t3.setId(UUID.randomUUID());
        assertThat(t1).isNotEqualTo(t3);
    }

    @Test
    @DisplayName("SecurityUtils: test all authentication branches")
    void shouldTestSecurityUtils() {
        SecurityContextHolder.clearContext();
        assertThat(SecurityUtils.getCurrentUsername()).isEmpty();

        TestingAuthenticationToken unauthenticated = new TestingAuthenticationToken("user", "pass");
        unauthenticated.setAuthenticated(false);
        SecurityContextHolder.getContext().setAuthentication(unauthenticated);
        assertThat(SecurityUtils.getCurrentUsername()).isEmpty();

        TestingAuthenticationToken stringPrincipal = new TestingAuthenticationToken("directUser", "pass");
        stringPrincipal.setAuthenticated(true);
        SecurityContextHolder.getContext().setAuthentication(stringPrincipal);
        assertThat(SecurityUtils.getCurrentUsername()).contains("directUser");

        User userDetails = new User("detailsUser", "pass", Collections.emptyList());
        TestingAuthenticationToken userDetailsAuth = new TestingAuthenticationToken(userDetails, "pass");
        userDetailsAuth.setAuthenticated(true);
        SecurityContextHolder.getContext().setAuthentication(userDetailsAuth);
        assertThat(SecurityUtils.getCurrentUsername()).contains("detailsUser");

        SecurityContextHolder.clearContext();
    }

    @Test
    @DisplayName("GlobalExceptionHandler: test unhandled and constraint exception handlers")
    void shouldTestGlobalExceptionHandler() {
        GlobalExceptionHandler handler = new GlobalExceptionHandler();

        ResponseEntity<ProblemDetail> res1 = handler.handleGenericException(new RuntimeException("Crash"));
        assertThat(res1.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);

        ResponseEntity<ProblemDetail> res2 = handler.handleDataIntegrity(new DataIntegrityViolationException("Unique key error"));
        assertThat(res2.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);

        ResponseEntity<ProblemDetail> res3 = handler.handleOptimisticLockFailure(new ObjectOptimisticLockingFailureException(Project.class, 1L));
        assertThat(res3.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);

        ResponseEntity<ProblemDetail> res4 = handler.handleAccessDenied(new AccessDeniedException("Forbidden"));
        assertThat(res4.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    @DisplayName("ETagUtils: test edge case branch coverage")
    void shouldTestETagUtilsBranches() {
        assertThat(ETagUtils.parseIfMatch("   ")).isNull();
        assertThat(ETagUtils.parseIfMatch("W/\"\"")).isNull();
        assertThat(ETagUtils.parseIfMatch("\"\"")).isNull();
        assertThat(ETagUtils.parseIfMatch("\"abc\"")).isNull();
    }
}
