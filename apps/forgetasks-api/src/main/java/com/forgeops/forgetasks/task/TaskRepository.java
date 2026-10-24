package com.forgeops.forgetasks.task;

import com.forgeops.forgetasks.account.Account;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

@Repository
public interface TaskRepository extends JpaRepository<Task, UUID> {

    @Query("SELECT t FROM Task t WHERE t.id = :id AND t.project.owner = :owner")
    Optional<Task> findByIdAndOwner(@Param("id") UUID id, @Param("owner") Account owner);

    @Query("SELECT t FROM Task t WHERE t.project.id = :projectId AND t.project.owner = :owner " +
           "AND (:status IS NULL OR t.status = :status) " +
           "AND (:priority IS NULL OR t.priority = :priority)")
    Page<Task> findByProjectIdAndOwnerWithFilters(
            @Param("projectId") UUID projectId,
            @Param("owner") Account owner,
            @Param("status") TaskStatus status,
            @Param("priority") TaskPriority priority,
            Pageable pageable
    );
}
