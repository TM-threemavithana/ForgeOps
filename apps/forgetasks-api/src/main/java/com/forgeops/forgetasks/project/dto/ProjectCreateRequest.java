package com.forgeops.forgetasks.project.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record ProjectCreateRequest(
        @NotBlank(message = "Project name cannot be blank")
        @Size(min = 1, max = 100, message = "Project name must be between 1 and 100 characters")
        String name,

        @Size(max = 2000, message = "Description cannot exceed 2000 characters")
        String description
) {}
