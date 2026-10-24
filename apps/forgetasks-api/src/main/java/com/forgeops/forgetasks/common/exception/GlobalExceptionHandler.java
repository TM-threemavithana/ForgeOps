package com.forgeops.forgetasks.common.exception;

import com.forgeops.forgetasks.common.correlation.RequestCorrelationFilter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.*;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.net.URI;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;

@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    private ProblemDetail createProblemDetail(HttpStatus status, String title, String detail, String typeSuffix) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(status, detail);
        problem.setTitle(title);
        problem.setType(URI.create("https://forgeops.local/errors/" + typeSuffix));
        problem.setProperty("timestamp", Instant.now());

        String correlationId = MDC.get(RequestCorrelationFilter.MDC_CORRELATION_KEY);
        if (correlationId != null) {
            problem.setProperty("correlationId", correlationId);
        }
        return problem;
    }

    @ExceptionHandler(ResourceNotFoundException.class)
    public ResponseEntity<ProblemDetail> handleResourceNotFound(ResourceNotFoundException ex) {
        log.info("Resource not found: {}", ex.getMessage());
        ProblemDetail problem = createProblemDetail(HttpStatus.NOT_FOUND, "Resource Not Found", ex.getMessage(), "resource-not-found");
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .contentType(MediaType.APPLICATION_PROBLEM_JSON)
                .body(problem);
    }

    @ExceptionHandler(PreconditionRequiredException.class)
    public ResponseEntity<ProblemDetail> handlePreconditionRequired(PreconditionRequiredException ex) {
        log.info("Precondition required: {}", ex.getMessage());
        ProblemDetail problem = createProblemDetail(HttpStatus.PRECONDITION_REQUIRED, "Precondition Required", ex.getMessage(), "precondition-required");
        return ResponseEntity.status(HttpStatus.PRECONDITION_REQUIRED)
                .contentType(MediaType.APPLICATION_PROBLEM_JSON)
                .body(problem);
    }

    @ExceptionHandler(PreconditionFailedException.class)
    public ResponseEntity<ProblemDetail> handlePreconditionFailed(PreconditionFailedException ex) {
        log.info("Precondition failed: {}", ex.getMessage());
        ProblemDetail problem = createProblemDetail(HttpStatus.PRECONDITION_FAILED, "Precondition Failed", ex.getMessage(), "precondition-failed");
        return ResponseEntity.status(HttpStatus.PRECONDITION_FAILED)
                .contentType(MediaType.APPLICATION_PROBLEM_JSON)
                .body(problem);
    }

    @ExceptionHandler(ConflictException.class)
    public ResponseEntity<ProblemDetail> handleConflict(ConflictException ex) {
        log.warn("Conflict: {}", ex.getMessage());
        ProblemDetail problem = createProblemDetail(HttpStatus.CONFLICT, "Conflict", ex.getMessage(), "conflict");
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .contentType(MediaType.APPLICATION_PROBLEM_JSON)
                .body(problem);
    }

    @ExceptionHandler(ObjectOptimisticLockingFailureException.class)
    public ResponseEntity<ProblemDetail> handleOptimisticLockFailure(ObjectOptimisticLockingFailureException ex) {
        log.warn("Optimistic locking collision detected: {}", ex.getMessage());
        ProblemDetail problem = createProblemDetail(HttpStatus.CONFLICT, "Optimistic Locking Collision",
                "The resource was modified by another concurrent transaction. Please refresh and retry.", "concurrent-modification-conflict");
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .contentType(MediaType.APPLICATION_PROBLEM_JSON)
                .body(problem);
    }

    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<ProblemDetail> handleDataIntegrity(DataIntegrityViolationException ex) {
        log.warn("Data integrity violation: {}", ex.getMessage());
        ProblemDetail problem = createProblemDetail(HttpStatus.CONFLICT, "Database Constraint Violation",
                "Operation violates a database integrity constraint (such as uniqueness).", "data-integrity-violation");
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .contentType(MediaType.APPLICATION_PROBLEM_JSON)
                .body(problem);
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ProblemDetail> handleValidation(MethodArgumentNotValidException ex) {
        Map<String, String> errors = new HashMap<>();
        for (FieldError error : ex.getBindingResult().getFieldErrors()) {
            errors.put(error.getField(), error.getDefaultMessage());
        }
        log.info("Validation failure on request: {}", errors);
        ProblemDetail problem = createProblemDetail(HttpStatus.BAD_REQUEST, "Validation Failure",
                "Request validation constraints failed.", "validation-failed");
        problem.setProperty("invalidParams", errors);
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .contentType(MediaType.APPLICATION_PROBLEM_JSON)
                .body(problem);
    }

    @ExceptionHandler(BadCredentialsException.class)
    public ResponseEntity<ProblemDetail> handleBadCredentials(BadCredentialsException ex) {
        log.warn("Authentication failed: invalid credentials");
        ProblemDetail problem = createProblemDetail(HttpStatus.UNAUTHORIZED, "Authentication Failed",
                "Invalid username or password.", "invalid-credentials");
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .contentType(MediaType.APPLICATION_PROBLEM_JSON)
                .body(problem);
    }

    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<ProblemDetail> handleAccessDenied(AccessDeniedException ex) {
        log.warn("Access denied: {}", ex.getMessage());
        ProblemDetail problem = createProblemDetail(HttpStatus.FORBIDDEN, "Access Denied",
                "You do not have permission to access this resource.", "access-denied");
        return ResponseEntity.status(HttpStatus.FORBIDDEN)
                .contentType(MediaType.APPLICATION_PROBLEM_JSON)
                .body(problem);
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ProblemDetail> handleGenericException(Exception ex) {
        log.error("Unhandled internal server error", ex);
        ProblemDetail problem = createProblemDetail(HttpStatus.INTERNAL_SERVER_ERROR, "Internal Server Error",
                "An unexpected internal error occurred. Please contact system support with your correlationId.", "internal-server-error");
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .contentType(MediaType.APPLICATION_PROBLEM_JSON)
                .body(problem);
    }
}
