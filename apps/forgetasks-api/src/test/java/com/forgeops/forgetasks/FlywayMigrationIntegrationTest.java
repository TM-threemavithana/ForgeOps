package com.forgeops.forgetasks;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class FlywayMigrationIntegrationTest extends AbstractIntegrationTest {

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Test
    @DisplayName("Flyway V1 Migration: creates accounts, projects, and tasks tables in PostgreSQL 16")
    void shouldVerifyDatabaseSchemaCreated() {
        List<String> tables = jdbcTemplate.queryForList(
                "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name",
                String.class
        );

        assertThat(tables).contains("accounts", "flyway_schema_history", "projects", "tasks");

        // Verify version column in projects
        Integer projectVersionCols = jdbcTemplate.queryForObject(
                "SELECT count(*) FROM information_schema.columns WHERE table_name = 'projects' AND column_name = 'version'",
                Integer.class
        );
        assertThat(projectVersionCols).isEqualTo(1);

        // Verify version column in tasks
        Integer taskVersionCols = jdbcTemplate.queryForObject(
                "SELECT count(*) FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'version'",
                Integer.class
        );
        assertThat(taskVersionCols).isEqualTo(1);

        // Verify unique constraint on accounts.username
        Integer uniqueConstraints = jdbcTemplate.queryForObject(
                "SELECT count(*) FROM information_schema.table_constraints WHERE table_name = 'accounts' AND constraint_type = 'UNIQUE'",
                Integer.class
        );
        assertThat(uniqueConstraints).isGreaterThanOrEqualTo(1);
    }
}
