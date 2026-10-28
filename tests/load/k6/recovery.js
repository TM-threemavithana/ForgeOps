import { sleep } from 'k6';
import { DEFAULT_TARGET_URL, DEFAULT_ENDPOINT, executeRequest } from './common.js';

export const options = {
    scenarios: {
        recovery_observation: {
            executor: 'constant-vus',
            vus: 2,
            duration: '30s',
        },
    },
    thresholds: {
        // Post-stress baseline recovery expectations
        http_req_failed: ['rate<0.01'],
        http_req_duration: ['p(50)<100', 'p(95)<200', 'p(99)<350'],
    },
};

export default function () {
    const url = `${DEFAULT_TARGET_URL}${DEFAULT_ENDPOINT}`;
    executeRequest(url, 200);
    sleep(0.25);
}
