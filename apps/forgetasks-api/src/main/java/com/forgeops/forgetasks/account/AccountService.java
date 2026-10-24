package com.forgeops.forgetasks.account;

import com.forgeops.forgetasks.account.dto.AccountRegistrationRequest;
import com.forgeops.forgetasks.account.dto.AccountResponse;
import com.forgeops.forgetasks.common.exception.ConflictException;
import com.forgeops.forgetasks.common.exception.ResourceNotFoundException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AccountService {

    private final AccountRepository accountRepository;
    private final PasswordEncoder passwordEncoder;

    public AccountService(AccountRepository accountRepository, PasswordEncoder passwordEncoder) {
        this.accountRepository = accountRepository;
        this.passwordEncoder = passwordEncoder;
    }

    @Transactional
    public AccountResponse registerAccount(AccountRegistrationRequest request) {
        if (accountRepository.existsByUsername(request.username())) {
            throw new ConflictException("Username '" + request.username() + "' is already registered.");
        }

        String passwordHash = passwordEncoder.encode(request.password());
        Account account = new Account(request.username(), passwordHash, "ROLE_USER");
        Account saved = accountRepository.save(account);
        return AccountResponse.from(saved);
    }

    @Transactional(readOnly = true)
    public Account getAccountByUsername(String username) {
        return accountRepository.findByUsername(username)
                .orElseThrow(() -> new ResourceNotFoundException("Account not found with username: " + username));
    }
}
