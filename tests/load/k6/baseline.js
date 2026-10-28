import { sleep } from 'k6';
import { DEFAULT_TARGET_URL, DEFAULT_ENDPOINT, executeRequest } from './common.js';

export const options = {
    scenarios: {
        baseline: {
            executor: 'constant-vus',
            vus: Number(__ENV.VUS || 5),
            duration: __ENV.DURATION || '45s',
        },
    },
    thresholds: {
        http_req_failed: ['rate<0.01'], // <1% failure
        http_req_duration: ['p(50)<100', 'p(95)<250', 'p(99)<500'], // tight latency bounds
    },
};

export default function () {
    const url = `${DEFAULT_TARGET_URL}${DEFAULT_ENDPOINT}`;
    executeRequest(url, 200);
    sleep(0.2);
}
