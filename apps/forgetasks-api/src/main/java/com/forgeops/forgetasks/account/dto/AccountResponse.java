package com.forgeops.forgetasks.account.dto;

import com.forgeops.forgetasks.account.Account;

import java.time.Instant;
import java.util.UUID;

public record AccountResponse(
        UUID id,
        String username,
        String role,
        Instant createdAt
) {
    public static AccountResponse from(Account account) {
        return new AccountResponse(
                account.getId(),
                account.getUsername(),
                account.getRole(),
                account.getCreatedAt()
        );
    }
}
