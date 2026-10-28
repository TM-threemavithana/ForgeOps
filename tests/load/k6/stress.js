import { DEFAULT_TARGET_URL, DEFAULT_ENDPOINT, executeRequest } from './common.js';

export const options = {
    scenarios: {
        bounded_stress: {
            executor: 'ramping-arrival-rate',
            startRate: 5,
            timeUnit: '1s',
            preAllocatedVUs: 10,
            maxVUs: 25, // Bounded at strictly max 25 VUs (protects workstation cgroup)
            stages: [
                { duration: '15s', target: 10 }, // Ramp to 10 req/s
                { duration: '25s', target: 16 }, // Step to 16 req/s
                { duration: '25s', target: 20 }, // Bounded peak at strictly 20 req/s ceiling
                { duration: '15s', target: 2 },  // Recovery ramp down
            ],
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
}
