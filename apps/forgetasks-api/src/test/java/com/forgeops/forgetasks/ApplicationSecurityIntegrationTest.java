package com.forgeops.forgetasks;

import tools.jackson.databind.JsonNode;
import com.forgeops.forgetasks.account.dto.AccountRegistrationRequest;
import com.forgeops.forgetasks.project.dto.ProjectCreateRequest;
import com.forgeops.forgetasks.project.dto.ProjectUpdateRequest;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.security.web.FilterChainProxy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.csrf.CookieCsrfTokenRepository;
import org.springframework.security.web.csrf.CsrfFilter;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MvcResult;

import jakarta.servlet.Filter;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class ApplicationSecurityIntegrationTest extends AbstractIntegrationTest {

    @Autowired
    private CookieCsrfTokenRepository csrfTokenRepository;

    @Autowired
    private FilterChainProxy filterChainProxy;

    @BeforeEach
    void resetCsrfTokenRepository() {
        restoreCookieCsrfTokenRepository();
    }

    private void restoreCookieCsrfTokenRepository() {
        if (filterChainProxy != null) {
            for (SecurityFilterChain chain : filterChainProxy.getFilterChains()) {
                for (Filter filter : chain.getFilters()) {
                    if (filter instanceof CsrfFilter) {
                        ReflectionTestUtils.setField(filter, "tokenRepository", csrfTokenRepository);
                    }
                }
            }
        }
    }

    @Test
    @DisplayName("AppSec: HTTP Security Headers are properly set on API responses (CSP, HSTS/Frame/Sniff/Referrer/Permissions)")
    void shouldEnforceSecurityHeaders() throws Exception {
        mockMvc.perform(get("/actuator/health"))
                .andExpect(status().isOk())
                .andExpect(header().string("X-Content-Type-Options", "nosniff"))
                .andExpect(header().string("X-Frame-Options", "DENY"))
                .andExpect(header().string("Referrer-Policy", "strict-origin-when-cross-origin"))
                .andExpect(header().string("Permissions-Policy", "geolocation=(), camera=(), microphone=(), payment=()"))
                .andExpect(header().exists("Content-Security-Policy"))
                .andExpect(header().string("Content-Security-Policy",
                        org.hamcrest.Matchers.containsString("default-src 'self'")))
                .andExpect(header().string("Content-Security-Policy",
                        org.hamcrest.Matchers.containsString("frame-ancestors 'none'")));
    }

    @Test
    @DisplayName("AppSec: CORS Preflight allows authorized local development origin and exposes required headers")
    void shouldEnforceControlledCorsForAllowedOrigin() throws Exception {
        mockMvc.perform(options("/api/v1/projects")
                        .header("Origin", "http://localhost:3000")
                        .header("Access-Control-Request-Method", "POST")
                        .header("Access-Control-Request-Headers", "Authorization,Content-Type,If-Match"))
                .andExpect(status().isOk())
                .andExpect(header().string("Access-Control-Allow-Origin", "http://localhost:3000"))
                .andExpect(header().string("Access-Control-Allow-Credentials", "true"))
                .andExpect(header().string("Access-Control-Expose-Headers",
                        org.hamcrest.Matchers.containsString("ETag")));
    }

    @Test
    @DisplayName("AppSec: CORS Preflight rejects unauthorized external origins")
    void shouldRejectCorsForDisallowedOrigin() throws Exception {
        mockMvc.perform(options("/api/v1/projects")
                        .header("Origin", "https://malicious-attacker.com")
                        .header("Access-Control-Request-Method", "POST"))
                .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("AppSec: Broken Object-Level Authorization (BOLA/IDOR) - User B cannot read, update, or delete User A's resources")
    void shouldEnforceObjectLevelAccessControl_BOLA_IDOR_Isolation() throws Exception {
        // 1. Register User A
        String userA = "sec_user_a_" + UUID.randomUUID().toString().substring(0, 8);
        String passA = "Password123!";
        mockMvc.perform(post("/api/v1/accounts")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new AccountRegistrationRequest(userA, passA))))
                .andExpect(status().isCreated());
        String authA = basicAuthHeader(userA, passA);

        // 2. User A creates Project A
        MvcResult projectResult = mockMvc.perform(post("/api/v1/projects")
                        .with(csrf())
                        .header(HttpHeaders.AUTHORIZATION, authA)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new ProjectCreateRequest("User A Confidential Project", "Restricted details"))))
                .andExpect(status().isCreated())
                .andExpect(header().exists(HttpHeaders.ETAG))
                .andReturn();

        JsonNode projectNode = objectMapper.readTree(projectResult.getResponse().getContentAsString());
        String projectAId = projectNode.get("id").asText();
        String etagA = projectResult.getResponse().getHeader(HttpHeaders.ETAG);

        // 3. Register User B
        String userB = "sec_user_b_" + UUID.randomUUID().toString().substring(0, 8);
        String passB = "Password123!";
        mockMvc.perform(post("/api/v1/accounts")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new AccountRegistrationRequest(userB, passB))))
                .andExpect(status().isCreated());
        String authB = basicAuthHeader(userB, passB);

        // 4. Attack 1: User B attempts to read Project A (IDOR GET) -> Expect 404 Not Found (zero information disclosure)
        mockMvc.perform(get("/api/v1/projects/" + projectAId)
                        .header(HttpHeaders.AUTHORIZATION, authB))
                .andExpect(status().isNotFound())
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.title").value("Resource Not Found"))
                .andExpect(jsonPath("$.correlationId").exists());

        // 5. Attack 2: User B attempts to modify Project A (IDOR PATCH) -> Expect 404 Not Found
        mockMvc.perform(patch("/api/v1/projects/" + projectAId)
                        .with(csrf())
                        .header(HttpHeaders.AUTHORIZATION, authB)
                        .header(HttpHeaders.IF_MATCH, etagA)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new ProjectUpdateRequest("Tampered Project Name", "Hacked description", null))))
                .andExpect(status().isNotFound())
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON));

        // 6. Attack 3: User B attempts to delete Project A (IDOR DELETE) -> Expect 404 Not Found
        mockMvc.perform(delete("/api/v1/projects/" + projectAId)
                        .with(csrf())
                        .header(HttpHeaders.AUTHORIZATION, authB)
                        .header(HttpHeaders.IF_MATCH, etagA))
                .andExpect(status().isNotFound())
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON));

        // 7. Verify Project A remains unmutated for User A
        mockMvc.perform(get("/api/v1/projects/" + projectAId)
                        .header(HttpHeaders.AUTHORIZATION, authA))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("User A Confidential Project"));
    }

    @Test
    @DisplayName("AppSec: Input validation rejects malformed usernames, special characters (XSS/SQLi vectors), and short passwords")
    void shouldRejectInvalidInputsWithProblemDetail() throws Exception {
        // Attempt XSS vector in username
        mockMvc.perform(post("/api/v1/accounts")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new AccountRegistrationRequest("user<script>alert(1)</script>", "Password123!"))))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.title").value("Validation Failure"))
                .andExpect(jsonPath("$.invalidParams.username").exists());

        // Attempt short password (< 8 chars)
        mockMvc.perform(post("/api/v1/accounts")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new AccountRegistrationRequest("valid_user_name", "short"))))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.title").value("Validation Failure"))
                .andExpect(jsonPath("$.invalidParams.password").exists());

        // Attempt blank username
        mockMvc.perform(post("/api/v1/accounts")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new AccountRegistrationRequest("", "Password123!"))))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.invalidParams.username").exists());
    }

    @Test
    @DisplayName("AppSec: Information Disclosure Prevention - Malformed UUID returns ProblemDetail without internal stack traces")
    void shouldPreventInformationDisclosureOnMalformedInputs() throws Exception {
        String user = "sec_user_err_" + UUID.randomUUID().toString().substring(0, 8);
        String pass = "Password123!";
        mockMvc.perform(post("/api/v1/accounts")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new AccountRegistrationRequest(user, pass))))
                .andExpect(status().isCreated());
        String auth = basicAuthHeader(user, pass);

        MvcResult result = mockMvc.perform(get("/api/v1/projects/not-a-valid-uuid")
                        .header(HttpHeaders.AUTHORIZATION, auth))
                .andReturn();

        // Response should be 400 Bad Request or 500 without stack trace
        String content = result.getResponse().getContentAsString();
        assertThat(content).doesNotContain("org.springframework");
        assertThat(content).doesNotContain("Exception at");
        assertThat(content).doesNotContain("com.forgeops");
        assertThat(content).doesNotContain("Hibernate");
    }

    @Test
    @DisplayName("AppSec: CSRF Protection - State-changing request lacking API Authorization header and CSRF token is rejected with 403 Forbidden")
    void shouldRejectStateChangingRequestWithoutCsrfTokenWhenLackingApiAuthorization() throws Exception {
        // Attempt state-changing POST without explicit API Basic Authorization header and without CSRF token
        mockMvc.perform(post("/api/v1/projects")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new ProjectCreateRequest("CSRF Project", "Malicious"))))
                .andExpect(status().isForbidden())
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.title").value("Forbidden"));
    }

    @Test
    @DisplayName("AppSec: CSRF Protection - State-changing request with valid CSRF token passes CSRF validation")
    void shouldAcceptStateChangingRequestWithValidCsrfToken() throws Exception {
        // Request with valid CSRF token passes CsrfFilter and proceeds to Authentication layer (yielding 401 Unauthorized since no credentials provided)
        mockMvc.perform(post("/api/v1/projects")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new ProjectCreateRequest("Valid CSRF Project", "Legitimate"))))
                .andExpect(status().isUnauthorized())
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.title").value("Unauthorized"));
    }

    @Test
    @DisplayName("AppSec: CSRF Protection - Browser-style authenticated request with cached Basic credentials but lacking CSRF token is rejected with 403 Forbidden")
    void shouldRejectBrowserStyleAuthenticatedRequestLackingCsrfToken() throws Exception {
        // 1. Register valid user to obtain valid credentials
        String user = "csrf_user_" + UUID.randomUUID().toString().substring(0, 8);
        String pass = "Password123!";
        mockMvc.perform(post("/api/v1/accounts")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new AccountRegistrationRequest(user, pass))))
                .andExpect(status().isCreated());
        String auth = basicAuthHeader(user, pass);

        // 2. Simulate browser-credential replay / cross-site request (carrying Authorization: Basic AND browser headers)
        mockMvc.perform(post("/api/v1/projects")
                        .header(HttpHeaders.AUTHORIZATION, auth)
                        .header("Sec-Fetch-Mode", "navigate")
                        .header(HttpHeaders.ORIGIN, "http://localhost:3000")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new ProjectCreateRequest("Replayed Project", "Malicious"))))
                .andExpect(status().isForbidden())
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.title").value("Forbidden"));
    }

    @Test
    @DisplayName("AppSec: CSRF Protection - Browser-style authenticated request with valid CSRF token succeeds")
    void shouldAcceptBrowserStyleAuthenticatedRequestWithValidCsrfToken() throws Exception {
        String user = "csrf_legit_" + UUID.randomUUID().toString().substring(0, 8);
        String pass = "Password123!";
        mockMvc.perform(post("/api/v1/accounts")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new AccountRegistrationRequest(user, pass))))
                .andExpect(status().isCreated());
        String auth = basicAuthHeader(user, pass);

        // Legitimate browser client providing both valid credentials and valid CSRF token
        mockMvc.perform(post("/api/v1/projects")
                        .with(csrf())
                        .header(HttpHeaders.AUTHORIZATION, auth)
                        .header("Sec-Fetch-Mode", "cors")
                        .header(HttpHeaders.ORIGIN, "http://localhost:3000")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new ProjectCreateRequest("Legit Browser Project", "Legit"))))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.name").value("Legit Browser Project"));
    }

    @Test
    @DisplayName("AppSec: CSRF Protection - Authenticated Basic request lacking browser headers and lacking CSRF token is rejected with 403 Forbidden")
    void shouldRejectAuthenticatedBasicRequestLackingBrowserHeadersAndCsrfToken() throws Exception {
        String user = "csrf_failclosed_" + UUID.randomUUID().toString().substring(0, 8);
        String pass = "Password123!";
        mockMvc.perform(post("/api/v1/accounts")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new AccountRegistrationRequest(user, pass))))
                .andExpect(status().isCreated());
        String auth = basicAuthHeader(user, pass);

        // State-changing request with Authorization: Basic, but without any browser headers (no Origin, no Referer, no Cookie, no Sec-Fetch-*)
        // In fail-closed CSRF, this must STILL be rejected with 403 Forbidden
        mockMvc.perform(post("/api/v1/projects")
                        .header(HttpHeaders.AUTHORIZATION, auth)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new ProjectCreateRequest("No Header Project", "Attempted bypass"))))
                .andExpect(status().isForbidden())
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.title").value("Forbidden"));
    }

    @Test
    @DisplayName("AppSec: CSRF Protection - Legitimate API client can obtain CSRF token via GET /api/v1/csrf and submit it for state-changing operations")
    void shouldAllowApiClientToObtainAndSubmitCsrfToken() throws Exception {
        String user = "csrf_client_" + UUID.randomUUID().toString().substring(0, 8);
        String pass = "Password123!";
        mockMvc.perform(post("/api/v1/accounts")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new AccountRegistrationRequest(user, pass))))
                .andExpect(status().isCreated());
        String auth = basicAuthHeader(user, pass);

        // Step 1: Client calls GET /api/v1/csrf to obtain the CSRF token metadata and cookie
        MvcResult csrfResult = mockMvc.perform(get("/api/v1/csrf"))
                .andExpect(status().isOk())
                .andExpect(cookie().exists("XSRF-TOKEN"))
                .andExpect(jsonPath("$.token").exists())
                .andExpect(jsonPath("$.headerName").exists())
                .andReturn();

        // Restore CookieCsrfTokenRepository on the test filter in case previous tests with .with(csrf()) replaced it
        restoreCookieCsrfTokenRepository();

        JsonNode csrfNode = objectMapper.readTree(csrfResult.getResponse().getContentAsString());
        String csrfToken = csrfNode.get("token").asText();
        String headerName = csrfNode.get("headerName").asText();
        assertThat(headerName).isIn("X-XSRF-TOKEN", "X-CSRF-TOKEN");
        jakarta.servlet.http.Cookie xsrfCookie = csrfResult.getResponse().getCookie("XSRF-TOKEN");
        assertThat(xsrfCookie).isNotNull();

        // Step 2: Client submits state-changing request carrying Authorization: Basic, cookie, and the returned CSRF token header
        mockMvc.perform(post("/api/v1/projects")
                        .header(HttpHeaders.AUTHORIZATION, auth)
                        .header(headerName, csrfToken)
                        .header("X-XSRF-TOKEN", csrfToken)
                        .cookie(xsrfCookie)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new ProjectCreateRequest("API Client Project", "Created via CSRF flow"))))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.name").value("API Client Project"));
    }
}
