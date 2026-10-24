package com.forgeops.forgetasks.project.dto;

import com.forgeops.forgetasks.project.Project;

import java.time.Instant;
import java.util.UUID;

public record ProjectResponse(
        UUID id,
        String name,
        String description,
        Long version,
        Instant createdAt,
        Instant updatedAt,
        Instant archivedAt
) {
    public static ProjectResponse from(Project project) {
        return new ProjectResponse(
                project.getId(),
                project.getName(),
                project.getDescription(),
                project.getVersion(),
                project.getCreatedAt(),
                project.getUpdatedAt(),
                project.getArchivedAt()
        );
    }
}
