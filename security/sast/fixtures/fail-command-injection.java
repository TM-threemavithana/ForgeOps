package com.forgeops.security.tests;

import java.io.IOException;

/**
 * Synthetic negative test for command injection detection.
 * MUST be flagged by forgeops.java.security.command-injection.
 */
public class FailCommandInjection {

    public void unsafeExec(String userArgument) throws IOException {
        // Vulnerable: dynamic command execution
        Runtime.getRuntime().exec("ping -c 1 " + userArgument);
    }
}
