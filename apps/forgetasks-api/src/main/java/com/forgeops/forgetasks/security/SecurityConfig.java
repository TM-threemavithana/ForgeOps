package com.forgeops.forgetasks.security;

import tools.jackson.databind.ObjectMapper;
import com.forgeops.forgetasks.common.correlation.RequestCorrelationFilter;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.MDC;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ProblemDetail;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.access.AccessDeniedHandler;

import java.net.URI;
import java.time.Instant;

@Configuration
@EnableWebSecurity
@EnableMethodSecurity
public class SecurityConfig {

    private final ObjectMapper objectMapper;

    public SecurityConfig(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder(12);
    }

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
                .csrf(AbstractHttpConfigurer::disable)
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        // Public Account Registration
                        .requestMatchers(HttpMethod.POST, "/api/v1/accounts").permitAll()
                        // Observability & Probes
                        .requestMatchers("/actuator/health/**", "/actuator/info", "/actuator/prometheus").permitAll()
                        // Restricted Management Endpoints
                        .requestMatchers("/actuator/**").hasRole("ADMIN")
                        // Protected Business APIs
                        .requestMatchers("/api/v1/**").authenticated()
                        .anyRequest().authenticated()
                )
                .httpBasic(basic -> basic.authenticationEntryPoint(problemAuthenticationEntryPoint()))
                .exceptionHandling(ex -> ex
                        .authenticationEntryPoint(problemAuthenticationEntryPoint())
                        .accessDeniedHandler(problemAccessDeniedHandler())
                );

        return http.build();
    }

    @Bean
    public AuthenticationEntryPoint problemAuthenticationEntryPoint() {
        return (request, response, authException) -> {
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            response.setContentType(MediaType.APPLICATION_PROBLEM_JSON_VALUE);

            ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                    HttpStatus.UNAUTHORIZED,
                    "Full authentication is required to access this resource."
            );
            problem.setTitle("Unauthorized");
            problem.setType(URI.create("https://forgeops.local/errors/unauthorized"));
            problem.setProperty("timestamp", Instant.now());

            String correlationId = MDC.get(RequestCorrelationFilter.MDC_CORRELATION_KEY);
            if (correlationId != null) {
                problem.setProperty("correlationId", correlationId);
            }

            response.getWriter().write(objectMapper.writeValueAsString(problem));
        };
    }

    @Bean
    public AccessDeniedHandler problemAccessDeniedHandler() {
        return (request, response, accessDeniedException) -> {
            response.setStatus(HttpServletResponse.SC_FORBIDDEN);
            response.setContentType(MediaType.APPLICATION_PROBLEM_JSON_VALUE);

            ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                    HttpStatus.FORBIDDEN,
                    "You do not possess the required permissions to access this resource."
            );
            problem.setTitle("Forbidden");
            problem.setType(URI.create("https://forgeops.local/errors/forbidden"));
            problem.setProperty("timestamp", Instant.now());

            String correlationId = MDC.get(RequestCorrelationFilter.MDC_CORRELATION_KEY);
            if (correlationId != null) {
                problem.setProperty("correlationId", correlationId);
            }

            response.getWriter().write(objectMapper.writeValueAsString(problem));
        };
    }
}
