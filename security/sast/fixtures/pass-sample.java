package com.forgeops.security.tests;

import java.io.File;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import javax.crypto.Cipher;
import javax.crypto.NoSuchPaddingException;
import jakarta.persistence.EntityManager;
import jakarta.persistence.TypedQuery;

/**
 * Synthetic compliant Java sample demonstrating secure coding patterns.
 * This file MUST pass all ForgeOps SAST security rules with zero findings.
 */
public class PassSample {

    public void queryWithParameters(EntityManager em, String accountId) {
        // Secure: Parameterized query (no dynamic string concatenation)
        TypedQuery<Object> query = em.createQuery("SELECT a FROM Account a WHERE a.id = :accountId", Object.class);
        query.setParameter("accountId", accountId);
        query.getResultList();
    }

    public void secureHashing() throws NoSuchAlgorithmException {
        // Secure: Strong cryptographic hash algorithm
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        digest.update("safe-data".getBytes());
    }

    public void secureCipher() throws NoSuchAlgorithmException, NoSuchPaddingException {
        // Secure: Modern authenticated encryption algorithm
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
    }

    public void safePathHandling(String sanitizedFilename) {
        // Secure: Path resolved against a fixed base without dynamic string concatenation
        Path basePath = Paths.get("/var/data/uploads");
        Path resolvedPath = basePath.resolve(sanitizedFilename).normalize();
        File file = resolvedPath.toFile();
    }
}
