package com.forgeops.forgetasks.account;

import com.forgeops.forgetasks.account.dto.AccountRegistrationRequest;
import com.forgeops.forgetasks.account.dto.AccountResponse;
import com.forgeops.forgetasks.common.exception.ConflictException;
import com.forgeops.forgetasks.common.exception.ResourceNotFoundException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class AccountServiceTest {

    @Mock
    private AccountRepository accountRepository;

    @Mock
    private PasswordEncoder passwordEncoder;

    private AccountService accountService;

    @BeforeEach
    void setUp() {
        accountService = new AccountService(accountRepository, passwordEncoder);
    }

    @Test
    @DisplayName("registerAccount: successfully registers new account with hashed password")
    void shouldRegisterNewAccount() {
        AccountRegistrationRequest request = new AccountRegistrationRequest("alice", "SecretPassword123!");
        when(accountRepository.existsByUsername("alice")).thenReturn(false);
        when(passwordEncoder.encode("SecretPassword123!")).thenReturn("$2a$12$hashedMockPassword");

        Account savedAccount = new Account("alice", "$2a$12$hashedMockPassword", "ROLE_USER");
        UUID accountId = UUID.randomUUID();
        savedAccount.setId(accountId);
        when(accountRepository.save(any(Account.class))).thenReturn(savedAccount);

        AccountResponse response = accountService.registerAccount(request);

        assertThat(response).isNotNull();
        assertThat(response.id()).isEqualTo(accountId);
        assertThat(response.username()).isEqualTo("alice");
        assertThat(response.role()).isEqualTo("ROLE_USER");
        verify(accountRepository).save(any(Account.class));
    }

    @Test
    @DisplayName("registerAccount: throws ConflictException when username already taken")
    void shouldRejectDuplicateUsername() {
        AccountRegistrationRequest request = new AccountRegistrationRequest("existingUser", "SecretPassword123!");
        when(accountRepository.existsByUsername("existingUser")).thenReturn(true);

        assertThatThrownBy(() -> accountService.registerAccount(request))
                .isInstanceOf(ConflictException.class)
                .hasMessageContaining("already registered");

        verify(accountRepository, never()).save(any(Account.class));
    }

    @Test
    @DisplayName("getAccountByUsername: returns account if exists, throws 404 if not found")
    void shouldFindAccountOrThrowNotFound() {
        Account account = new Account("bob", "hash", "ROLE_USER");
        when(accountRepository.findByUsername("bob")).thenReturn(Optional.of(account));
        when(accountRepository.findByUsername("unknown")).thenReturn(Optional.empty());

        assertThat(accountService.getAccountByUsername("bob")).isEqualTo(account);
        assertThatThrownBy(() -> accountService.getAccountByUsername("unknown"))
                .isInstanceOf(ResourceNotFoundException.class);
    }
}
