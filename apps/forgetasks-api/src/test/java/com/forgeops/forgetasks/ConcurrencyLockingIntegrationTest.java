package com.forgeops.forgetasks;

import com.forgeops.forgetasks.account.AccountService;
import com.forgeops.forgetasks.account.dto.AccountRegistrationRequest;
import com.forgeops.forgetasks.common.exception.PreconditionFailedException;
import com.forgeops.forgetasks.project.ProjectService;
import com.forgeops.forgetasks.project.dto.ProjectCreateRequest;
import com.forgeops.forgetasks.project.dto.ProjectResponse;
import com.forgeops.forgetasks.project.dto.ProjectUpdateRequest;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.orm.ObjectOptimisticLockingFailureException;

import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;

class ConcurrencyLockingIntegrationTest extends AbstractIntegrationTest {

    @Autowired
    private ProjectService projectService;

    @Autowired
    private AccountService accountService;

    @Test
    @DisplayName("Concurrency: parallel updates with same initial If-Match prevent lost updates (one succeeds, one rejected)")
    void shouldPreventLostUpdatesUnderConcurrentModifications() throws InterruptedException {
        String user = "concurrent_user_" + UUID.randomUUID().toString().substring(0, 8);
        String pass = "Password123!";

        accountService.registerAccount(new AccountRegistrationRequest(user, pass));

        // Create project with initial version 0
        ProjectResponse created = projectService.createProject(
                new ProjectCreateRequest("Concurrent Project", "Concurrency test"), user
        );
        UUID projectId = created.id();
        assertThat(created.version()).isEqualTo(0L);

        int threadCount = 2;
        ExecutorService executor = Executors.newFixedThreadPool(threadCount);
        CountDownLatch readyLatch = new CountDownLatch(threadCount);
        CountDownLatch startLatch = new CountDownLatch(1);

        AtomicInteger successCount = new AtomicInteger(0);
        AtomicInteger failureCount = new AtomicInteger(0);

        for (int i = 0; i < threadCount; i++) {
            final int threadIndex = i;
            executor.submit(() -> {
                readyLatch.countDown();
                try {
                    startLatch.await(); // Synchronize parallel start

                    ProjectUpdateRequest updateReq = new ProjectUpdateRequest("Name by Thread " + threadIndex, null, null);
                    projectService.updateProject(projectId, user, updateReq, 0L);
                    successCount.incrementAndGet();
                } catch (PreconditionFailedException | ObjectOptimisticLockingFailureException e) {
                    failureCount.incrementAndGet();
                } catch (Exception e) {
                    failureCount.incrementAndGet();
                }
            });
        }

        readyLatch.await(5, TimeUnit.SECONDS);
        startLatch.countDown(); // Fire both updates simultaneously

        executor.shutdown();
        boolean finished = executor.awaitTermination(10, TimeUnit.SECONDS);
        assertThat(finished).isTrue();

        // Exactly one update must succeed, and the other must be rejected
        assertThat(successCount.get()).isEqualTo(1);
        assertThat(failureCount.get()).isEqualTo(1);

        // Fetch final state: version must be exactly 1, no lost updates
        ProjectResponse finalProject = projectService.getProject(projectId, user);
        assertThat(finalProject.version()).isEqualTo(1L);
    }
}
