package com.forgeops.security.tests;

import java.io.File;

/**
 * Synthetic negative test for path traversal detection.
 * MUST be flagged by forgeops.java.security.path-traversal.
 */
public class FailPathTraversal {

    public File unsafeFileOpen(String userInput) {
        // Vulnerable: Direct string concatenation into File constructor
        return new File("/var/storage/" + userInput);
    }
}
