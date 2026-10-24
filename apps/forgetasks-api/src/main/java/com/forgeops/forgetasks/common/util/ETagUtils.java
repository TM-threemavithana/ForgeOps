package com.forgeops.forgetasks.common.util;

public final class ETagUtils {

    private ETagUtils() {
    }

    public static String formatETag(Long version) {
        if (version == null) {
            return "\"0\"";
        }
        return "\"" + version + "\"";
    }

    public static Long parseIfMatch(String ifMatchHeader) {
        if (ifMatchHeader == null || ifMatchHeader.isBlank()) {
            return null;
        }

        String cleaned = ifMatchHeader.trim();
        // Remove surrounding quotes if present
        if (cleaned.startsWith("\"") && cleaned.endsWith("\"") && cleaned.length() >= 2) {
            cleaned = cleaned.substring(1, cleaned.length() - 1);
        }

        // Handle weak prefix W/
        if (cleaned.startsWith("W/\"") && cleaned.endsWith("\"") && cleaned.length() >= 4) {
            cleaned = cleaned.substring(3, cleaned.length() - 1);
        }

        try {
            return Long.parseLong(cleaned);
        } catch (NumberFormatException e) {
            return null;
        }
    }
}
