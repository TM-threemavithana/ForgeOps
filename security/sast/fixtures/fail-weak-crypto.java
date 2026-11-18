package com.forgeops.security.tests;

import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import javax.crypto.Cipher;
import javax.crypto.NoSuchPaddingException;

/**
 * Synthetic negative test for weak cryptography and hashing.
 * MUST be flagged by forgeops.java.security.weak-crypto and forgeops.java.security.insecure-hash.
 */
public class FailWeakCrypto {

    public void unsafeCipher() throws NoSuchAlgorithmException, NoSuchPaddingException {
        // Vulnerable: Deprecated DES encryption
        Cipher cipher = Cipher.getInstance("DES/CBC/PKCS5Padding");
    }

    public void unsafeHash() throws NoSuchAlgorithmException {
        // Vulnerable: Deprecated MD5 hashing
        MessageDigest md5 = MessageDigest.getInstance("MD5");
    }
}
