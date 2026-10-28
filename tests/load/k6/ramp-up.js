import { sleep } from 'k6';
import { DEFAULT_TARGET_URL, DEFAULT_ENDPOINT, executeRequest } from './common.js';

export const options = {
    scenarios: {
        ramp_up: {
            executor: 'ramping-vus',
            startVUs: 1,
            stages: [
                { duration: '10s', target: 3 },  // Initial warm-up
                { duration: '20s', target: 8 },  // Moderate concurrency
                { duration: '20s', target: 15 }, // Steeper concurrency
                { duration: '15s', target: 20 }, // Peak ramp concurrency
                { duration: '10s', target: 0 },  // Graceful wind-down
            ],
            gracefulRampDown: '5s',
        },
    },
    thresholds: {
        http_req_failed: ['rate<0.02'], // <2% failure
        http_req_duration: ['p(95)<400', 'p(99)<750'], // latency limits under load
    },
};

export default function () {
    const url = `${DEFAULT_TARGET_URL}${DEFAULT_ENDPOINT}`;
    executeRequest(url, 200);
    sleep(0.1);
}
