package com.forgeops.forgetasks;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class FlywayMigrationRunnerTest extends AbstractIntegrationTest {

    @Test
    @DisplayName("Should return 1 on insufficient arguments")
    void shouldReturnOneOnInsufficientArguments() {
        assertThat(FlywayMigrationRunner.run(null)).isEqualTo(1);
        assertThat(FlywayMigrationRunner.run(new String[]{})).isEqualTo(1);
        assertThat(FlywayMigrationRunner.run(new String[]{"migrate"})).isEqualTo(1);
        assertThat(FlywayMigrationRunner.run(new String[]{"migrate", "jdbc:url"})).isEqualTo(1);
    }

    @Test
    @DisplayName("Should return 1 on unknown action")
    void shouldReturnOneOnUnknownAction() {
        int result = FlywayMigrationRunner.run(new String[]{"invalidAction", postgres.getJdbcUrl(), postgres.getUsername(), postgres.getPassword()});
        assertThat(result).isEqualTo(1);
    }

    @Test
    @DisplayName("Should return 1 on invalid database connection")
    void shouldReturnOneOnConnectionFailure() {
        int result = FlywayMigrationRunner.run(new String[]{"migrate", "jdbc:postgresql://127.0.0.1:59999/nonexistent", "user", "pass"});
        assertThat(result).isEqualTo(1);
    }

    @Test
    @DisplayName("Should execute info and validate against PostgreSQL testcontainer")
    void shouldExecuteInfoAndValidationAgainstPostgres() {
        String url = postgres.getJdbcUrl();
        String user = postgres.getUsername();
        String pass = postgres.getPassword();

        // 1. Info
        int infoResult = FlywayMigrationRunner.run(new String[]{"info", url, user, pass});
        assertThat(infoResult).isEqualTo(0);

        // 2. Validate
        int validateResult = FlywayMigrationRunner.run(new String[]{"validate", url, user, pass});
        assertThat(validateResult).isEqualTo(0);

        // 3. Migrate (idempotent since schema is already migrated)
        int migrateResult = FlywayMigrationRunner.run(new String[]{"migrate", url, user, pass});
        assertThat(migrateResult).isEqualTo(0);
    }

    @Test
    @DisplayName("Should allow instance creation for code coverage completeness")
    void shouldInstantiateRunner() {
        FlywayMigrationRunner runner = new FlywayMigrationRunner();
        assertThat(runner).isNotNull();
    }
}
