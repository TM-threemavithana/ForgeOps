package com.forgeops.forgetasks.common.util;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class ETagUtilsTest {

    @Test
    @DisplayName("formatETag: correctly formats non-null and null versions")
    void shouldFormatETag() {
        assertThat(ETagUtils.formatETag(0L)).isEqualTo("\"0\"");
        assertThat(ETagUtils.formatETag(42L)).isEqualTo("\"42\"");
        assertThat(ETagUtils.formatETag(null)).isEqualTo("\"0\"");
    }

    @Test
    @DisplayName("parseIfMatch: parses quoted, unquoted, and weak ETags correctly")
    void shouldParseIfMatchHeader() {
        assertThat(ETagUtils.parseIfMatch("\"5\"")).isEqualTo(5L);
        assertThat(ETagUtils.parseIfMatch("5")).isEqualTo(5L);
        assertThat(ETagUtils.parseIfMatch("W/\"12\"")).isEqualTo(12L);
        assertThat(ETagUtils.parseIfMatch("   \"99\"  ")).isEqualTo(99L);
        assertThat(ETagUtils.parseIfMatch(null)).isNull();
        assertThat(ETagUtils.parseIfMatch("")).isNull();
        assertThat(ETagUtils.parseIfMatch("invalid")).isNull();
        assertThat(ETagUtils.parseIfMatch("\"")).isNull();
        assertThat(ETagUtils.parseIfMatch("\"unclosed")).isNull();
        assertThat(ETagUtils.parseIfMatch("unopened\"")).isNull();
        assertThat(ETagUtils.parseIfMatch("W/\"")).isNull();
        assertThat(ETagUtils.parseIfMatch("W/\"unclosed")).isNull();
        assertThat(ETagUtils.parseIfMatch("W/unopened\"")).isNull();
    }
}
