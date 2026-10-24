package com.forgeops.forgetasks.common.exception;

public class PreconditionRequiredException extends RuntimeException {
    public PreconditionRequiredException(String message) {
        super(message);
    }
}
