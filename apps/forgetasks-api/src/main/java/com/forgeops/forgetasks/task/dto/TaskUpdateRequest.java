package com.forgeops.forgetasks.task.dto;

import com.forgeops.forgetasks.task.TaskPriority;
import com.forgeops.forgetasks.task.TaskStatus;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.UUID;

public record TaskUpdateRequest(
        @Size(min = 1, max = 200, message = "Title must be between 1 and 200 characters")
        String title,

        @Size(max = 5000, message = "Description cannot exceed 5000 characters")
        String description,

        TaskStatus status,

        TaskPriority priority,

        UUID assignedAccountId,

        Instant dueDate
) {}
