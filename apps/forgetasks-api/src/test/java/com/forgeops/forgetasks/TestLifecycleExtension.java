package com.forgeops.forgetasks;

import org.junit.jupiter.api.extension.BeforeAllCallback;
import org.junit.jupiter.api.extension.ExtensionContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ConfigurableApplicationContext;

/**
 * JUnit 5 extension to manage clean global teardown of Spring ApplicationContext
 * and Testcontainers PostgreSQL instances at the end of the entire test execution,
 * preventing lingering resources and ensuring clean JVM termination without
 * relying on unmanaged shutdown hooks.
 */
public class TestLifecycleExtension implements BeforeAllCallback, AutoCloseable {

    private static final Logger log = LoggerFactory.getLogger(TestLifecycleExtension.class);
    private static final ExtensionContext.Namespace NAMESPACE = ExtensionContext.Namespace.create(TestLifecycleExtension.class);
    private static volatile boolean registered = false;
    private static volatile ConfigurableApplicationContext applicationContext;

    public static void setApplicationContext(ConfigurableApplicationContext ctx) {
        applicationContext = ctx;
    }

    @Override
    public void beforeAll(ExtensionContext context) {
        if (!registered) {
            registered = true;
            context.getRoot().getStore(NAMESPACE).put("testLifecycleResource", this);
        }
    }

    @Override
    public void close() {
        log.info("Executing clean test lifecycle teardown...");
        if (applicationContext != null && applicationContext.isActive()) {
            try {
                applicationContext.close();
                log.info("Spring ApplicationContext closed cleanly.");
            } catch (Exception e) {
                log.warn("Error closing Spring ApplicationContext during teardown: {}", e.getMessage());
            }
        }
        try {
            Class<?> rtClass = Class.forName("org.jacoco.agent.rt.RT");
            Object agent = rtClass.getMethod("getAgent").invoke(null);
            if (agent != null) {
                agent.getClass().getMethod("dump", boolean.class).invoke(agent, false);
                log.info("JaCoCo execution data dumped cleanly via lifecycle extension.");
            }
        } catch (ClassNotFoundException ignored) {
            // JaCoCo agent not loaded
        } catch (Exception e) {
            log.warn("Error dumping JaCoCo execution data: {}", e.getMessage());
        }

        if (AbstractIntegrationTest.postgres != null && AbstractIntegrationTest.postgres.isRunning()) {
            try {
                AbstractIntegrationTest.postgres.stop();
                log.info("PostgreSQL Testcontainer stopped cleanly.");
            } catch (Exception e) {
                log.warn("Error stopping PostgreSQL Testcontainer: {}", e.getMessage());
            }
        }
    }
}
