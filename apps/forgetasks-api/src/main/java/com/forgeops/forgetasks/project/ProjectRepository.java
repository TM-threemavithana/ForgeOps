package com.forgeops.forgetasks.project;

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
public interface ProjectRepository extends JpaRepository<Project, UUID> {

    Optional<Project> findByIdAndOwner(UUID id, Account owner);

    Page<Project> findByOwnerAndArchivedAtIsNull(Account owner, Pageable pageable);

    Page<Project> findByOwner(Account owner, Pageable pageable);

    boolean existsByIdAndOwner(UUID id, Account owner);

    @Query("SELECT p FROM Project p WHERE p.id = :id AND p.owner.id = :ownerId")
    Optional<Project> findByIdAndOwnerId(@Param("id") UUID id, @Param("ownerId") UUID ownerId);
}
