import { sleep } from 'k6';
import { DEFAULT_TARGET_URL, DEFAULT_ENDPOINT, executeRequest } from './common.js';

export const options = {
    scenarios: {
        bounded_stress: {
            executor: 'ramping-vus',
            startVUs: 2,
            stages: [
                { duration: '10s', target: 10 }, // Ramp to 10 VUs
                { duration: '20s', target: 20 }, // Step to 20 VUs
                { duration: '20s', target: 25 }, // Bounded peak at 25 VUs (workstation safe)
                { duration: '10s', target: 0 },  // Recovery ramp down
            ],
            gracefulRampDown: '5s',
        },
    },
    thresholds: {
        // Explicit abort thresholds to protect local workstation and cluster stability
        http_req_failed: [{ threshold: 'rate<0.05', abortOnFail: true }], // Abort if failure >5%
        http_req_duration: [
            { threshold: 'p(95)<1000', abortOnFail: true }, // Abort if p95 exceeds 1s
            'p(99)<2000',
        ],
    },
};

export default function () {
    const url = `${DEFAULT_TARGET_URL}${DEFAULT_ENDPOINT}`;
    executeRequest(url, 200);
    sleep(0.05);
}
