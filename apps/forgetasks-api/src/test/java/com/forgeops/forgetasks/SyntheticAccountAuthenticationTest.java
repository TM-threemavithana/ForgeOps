package com.forgeops.forgetasks;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.assertj.core.api.Assertions.assertThat;

class SyntheticAccountAuthenticationTest {

    private final PasswordEncoder encoder = new BCryptPasswordEncoder(12);

    @Test
    @DisplayName("Verify synthetic seed SQL contains valid BCrypt hashes matching synthetic smoke credentials")
    void shouldVerifySyntheticSeedBCryptHashes() throws IOException {
        Path seedSqlPath = Paths.get("../../platform/dr-lab/synthetic-seed.sql");
        if (!Files.exists(seedSqlPath)) {
            seedSqlPath = Paths.get("platform/dr-lab/synthetic-seed.sql");
        }
        assertThat(seedSqlPath).exists();

        String sqlContent = Files.readString(seedSqlPath);

        // Pattern matching: ('d0...', 'username', 'password_hash', 'ROLE_...')
        Pattern pattern = Pattern.compile("\\('([^']+)',\\s*'([^']+)',\\s*'(\\$2[ab]\\$12\\$[^']+)',\\s*'([^']+)'\\)");
        Matcher matcher = pattern.matcher(sqlContent);

        int accountsFound = 0;
        CharSequence expectedPassword = "Password123!";

        while (matcher.find()) {
            accountsFound++;
            String id = matcher.group(1);
            String username = matcher.group(2);
            String hash = matcher.group(3);
            String role = matcher.group(4);

            assertThat(username).isIn("dr_admin", "dr_user");
            assertThat(role).isIn("ROLE_ADMIN", "ROLE_USER");

            // Assert positive authentication against the synthetic password
            assertThat(encoder.matches(expectedPassword, hash))
                    .as("Positive authentication failed for synthetic account: " + username)
                    .isTrue();

            // Assert negative authentication against invalid passwords
            assertThat(encoder.matches("InvalidPassword", hash))
                    .as("Negative auth should fail for invalid password on account: " + username)
                    .isFalse();
            assertThat(encoder.matches("WrongPassword123!", hash))
                    .as("Negative auth should fail for wrong password on account: " + username)
                    .isFalse();
            assertThat(encoder.matches("", hash))
                    .as("Negative auth should fail for empty password on account: " + username)
                    .isFalse();
        }

        assertThat(accountsFound).isEqualTo(2);
    }
}
