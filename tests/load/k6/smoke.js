import { DEFAULT_TARGET_URL, DEFAULT_ENDPOINT, executeRequest } from './common.js';

export const options = {
    scenarios: {
        smoke: {
            executor: 'constant-arrival-rate',
            rate: 2, // 2 requests per second
            timeUnit: '1s',
            duration: '20s',
            preAllocatedVUs: 1,
            maxVUs: 2,
        },
    },
    thresholds: {
        http_req_failed: ['rate<0.01'], // <1% errors
        http_req_duration: ['p(95)<200', 'p(99)<350'], // 95% of requests under 200ms
    },
};

export default function () {
    const url = `${DEFAULT_TARGET_URL}${DEFAULT_ENDPOINT}`;
    executeRequest(url, 200);
}
