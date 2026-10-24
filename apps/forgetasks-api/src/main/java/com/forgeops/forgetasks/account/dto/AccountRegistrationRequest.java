package com.forgeops.forgetasks.account.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record AccountRegistrationRequest(
        @NotBlank(message = "Username cannot be blank")
        @Size(min = 3, max = 50, message = "Username must be between 3 and 50 characters")
        @Pattern(regexp = "^[a-zA-Z0-9_.-]+$", message = "Username may only contain letters, numbers, underscores, dots, and hyphens")
        String username,

        @NotBlank(message = "Password cannot be blank")
        @Size(min = 8, max = 100, message = "Password must be between 8 and 100 characters")
        String password
) {}
