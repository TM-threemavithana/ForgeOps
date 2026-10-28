import { DEFAULT_TARGET_URL, DEFAULT_ENDPOINT, executeRequest } from './common.js';

export const options = {
    scenarios: {
        ramp_up: {
            executor: 'ramping-arrival-rate',
            startRate: 2,
            timeUnit: '1s',
            preAllocatedVUs: 5,
            maxVUs: 20,
            stages: [
                { duration: '15s', target: 5 },  // Initial warm-up: 5 req/s
                { duration: '20s', target: 12 }, // Moderate rate: 12 req/s
                { duration: '20s', target: 18 }, // Steeper rate: 18 req/s (below 20 req/s ceiling)
                { duration: '15s', target: 2 },  // Wind down: 2 req/s
            ],
        },
    },
    thresholds: {
        http_req_failed: ['rate<0.02'], // <2% failure
        http_req_duration: ['p(95)<350', 'p(99)<750'], // latency limits under progressive load
    },
};

export default function () {
    const url = `${DEFAULT_TARGET_URL}${DEFAULT_ENDPOINT}`;
    executeRequest(url, 200);
}
