import { DEFAULT_TARGET_URL, DEFAULT_ENDPOINT, executeRequest } from './common.js';

export const options = {
    scenarios: {
        baseline: {
            executor: 'constant-arrival-rate',
            rate: 10, // 10 requests per second (well below 20 req/s ceiling)
            timeUnit: '1s',
            duration: __ENV.DURATION || '45s',
            preAllocatedVUs: 5,
            maxVUs: 10,
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
}
