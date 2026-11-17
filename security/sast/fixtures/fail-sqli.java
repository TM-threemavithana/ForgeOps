package com.forgeops.security.tests;

import jakarta.persistence.EntityManager;

/**
 * Synthetic negative test for SQL/JPQL injection detection.
 * MUST be flagged by forgeops.java.security.sql-injection.
 */
public class FailSqlInjection {

    public void unsafeQuery(EntityManager em, String userInput) {
        // Vulnerable: dynamic string concatenation into createQuery
        em.createQuery("SELECT t FROM Task t WHERE t.name = '" + userInput + "'", Object.class);
    }
}
