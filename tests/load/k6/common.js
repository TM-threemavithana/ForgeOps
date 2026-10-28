import http from 'k6/http';
import { check } from 'k6';

export const DEFAULT_TARGET_URL = __ENV.TARGET_URL || 'http://127.0.0.1:18080';
export const DEFAULT_ENDPOINT = __ENV.ENDPOINT || '/actuator/health/readiness';

function randomHex(length) {
    let result = '';
    const characters = '0123456789abcdef';
    for (let i = 0; i < length; i++) {
        result += characters.charAt(Math.floor(Math.random() * characters.length));
    }
    return result;
}

export function generateW3CTraceparent() {
    const traceId = randomHex(32);
    const spanId = randomHex(16);
    return `00-${traceId}-${spanId}-01`;
}

export function executeRequest(url, expectedStatus = 200, customHeaders = {}) {
    const correlationId = `req-k6-${__VU}-${__ITER}-${Date.now()}`;
    const traceparent = generateW3CTraceparent();

    const params = {
        headers: Object.assign({
            'User-Agent': 'k6-forgeops-g12/1.0',
            'Accept': 'application/json, text/plain, */*',
            'X-Request-ID': correlationId,
            'traceparent': traceparent,
        }, customHeaders),
        tags: {
            scenario: __ENV.SCENARIO_NAME || 'default',
        },
        timeout: '5s',
    };

    const res = http.get(url, params);

    check(res, {
        'status is expected': (r) => r.status === expectedStatus,
        'response received within 2s': (r) => r.timings.duration < 2000,
    });

    return res;
}
