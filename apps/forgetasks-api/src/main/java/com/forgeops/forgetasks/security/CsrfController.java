package com.forgeops.forgetasks.security;

import org.springframework.security.web.csrf.CsrfToken;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Controller providing anti-CSRF token metadata for legitimate API clients and SPAs.
 * Invoking this endpoint also forces evaluation of deferred CSRF tokens, causing
 * CookieCsrfTokenRepository to write the XSRF-TOKEN cookie.
 */
@RestController
@RequestMapping("/api/v1/csrf")
public class CsrfController {

    @GetMapping
    public Map<String, String> getCsrfToken(CsrfToken csrfToken) {
        if (csrfToken == null) {
            return Map.of();
        }
        return Map.of(
                "token", csrfToken.getToken(),
                "headerName", csrfToken.getHeaderName(),
                "parameterName", csrfToken.getParameterName()
        );
    }
}
