import { DEFAULT_TARGET_URL, DEFAULT_ENDPOINT, executeRequest } from './common.js';

export const options = {
    scenarios: {
        recovery: {
            executor: 'constant-arrival-rate',
            rate: 2, // 2 requests per second post-stress
            timeUnit: '1s',
            duration: '30s',
            preAllocatedVUs: 2,
            maxVUs: 5,
        },
    },
    thresholds: {
        http_req_failed: ['rate<0.01'],
        http_req_duration: ['p(95)<200', 'p(99)<350'],
    },
};

export default function () {
    const url = `${DEFAULT_TARGET_URL}${DEFAULT_ENDPOINT}`;
    executeRequest(url, 200);
}
