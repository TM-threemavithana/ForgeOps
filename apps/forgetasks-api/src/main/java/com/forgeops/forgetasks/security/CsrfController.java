package com.forgeops.forgetasks.security;

import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.security.web.csrf.CsrfToken;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Controller providing anti-CSRF token metadata for legitimate API clients and SPAs.
 * Invoking this endpoint forces evaluation of deferred CSRF tokens and ensures
 * the XSRF-TOKEN cookie is explicitly written to the response for clients to read and echo back.
 */
@RestController
@RequestMapping("/api/v1/csrf")
public class CsrfController {

    @GetMapping
    public Map<String, String> getCsrfToken(HttpServletRequest request, HttpServletResponse response) {
        CsrfToken csrfToken = (CsrfToken) request.getAttribute(CsrfToken.class.getName());
        if (csrfToken == null) {
            csrfToken = (CsrfToken) request.getAttribute("_csrf");
        }
        if (csrfToken == null) {
            return Map.of();
        }
        String token = csrfToken.getToken();
        Cookie cookie = new Cookie("XSRF-TOKEN", token);
        cookie.setPath("/");
        cookie.setHttpOnly(false);
        response.addCookie(cookie);

        return Map.of(
                "token", token,
                "headerName", csrfToken.getHeaderName(),
                "parameterName", csrfToken.getParameterName()
        );
    }
}
