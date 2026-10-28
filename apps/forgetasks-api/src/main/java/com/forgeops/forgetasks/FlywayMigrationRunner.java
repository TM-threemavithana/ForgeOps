package com.forgeops.forgetasks;

import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.output.MigrateResult;
import org.flywaydb.core.api.MigrationInfo;

public class FlywayMigrationRunner {

    public static void main(String[] args) {
        int exitCode = run(args);
        if (exitCode != 0) {
            System.exit(exitCode);
        }
    }

    public static int run(String[] args) {
        if (args == null || args.length < 3) {
            System.err.println("Usage: FlywayMigrationRunner <action: migrate|validate|info> <jdbc-url> <user> [password]");
            return 1;
        }

        String action = args[0];
        String url = args[1];
        String user = args[2];
        String pass = System.getenv("FLYWAY_PASSWORD");
        if (pass == null || pass.isEmpty()) {
            if (args.length >= 4) {
                pass = args[3];
            } else {
                pass = "";
            }
        }

        try {
            Flyway flyway = Flyway.configure()
                    .dataSource(url, user, pass)
                    .locations("classpath:db/migration")
                    .cleanDisabled(true)
                    .baselineOnMigrate(false)
                    .load();

            if ("migrate".equalsIgnoreCase(action)) {
                System.out.println("Running authentic Flyway migration against " + url + "...");
                MigrateResult result = flyway.migrate();
                System.out.println("Flyway migration completed successfully. Executed " + result.migrationsExecuted + " migrations.");
                return 0;
            } else if ("validate".equalsIgnoreCase(action)) {
                System.out.println("Running Flyway validation against " + url + "...");
                flyway.validate();
                System.out.println("Flyway validation PASSED successfully against genuine application migrations.");
                return 0;
            } else if ("info".equalsIgnoreCase(action)) {
                MigrationInfo current = flyway.info().current();
                if (current != null) {
                    System.out.println("Flyway current state: Version=" + current.getVersion() + ", Description=" + current.getDescription() + ", Checksum=" + current.getChecksum());
                } else {
                    System.out.println("Flyway current state: No migrations applied.");
                }
                return 0;
            } else {
                System.err.println("Unknown action: " + action + " (expected migrate, validate, or info)");
                return 1;
            }
        } catch (Exception e) {
            System.err.println("Flyway operation '" + action + "' failed: " + e.getMessage());
            e.printStackTrace();
            return 1;
        }
    }
}
