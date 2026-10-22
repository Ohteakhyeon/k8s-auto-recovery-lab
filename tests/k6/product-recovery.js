
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const productFailureRate = new Rate('product_failure_rate');

export const options = {
  vus: 1,
  duration: '90s',
};

let previousSuccess = null;
let consecutiveSuccesses = 0;

export default function () {
  const startedAt = new Date().toISOString();

  const response = http.get('http://localhost:8080/', {
    timeout: '3s',
  });

  const success =
    response.status === 200 &&
    response.body !== null &&
    response.body.includes('Hot Products') &&
    response.body.includes('Sunglasses');

  check(response, {
    '상품 조회 정상': () => success,
  });

  productFailureRate.add(!success);

  console.log(
    `SAMPLE time=${startedAt} success=${success} ` +
    `status=${response.status} duration=${response.timings.duration}ms`
  );

  if (success) {
    consecutiveSuccesses++;
  } else {
    consecutiveSuccesses = 0;
  }

  if (previousSuccess !== null && success !== previousSuccess) {
    console.log(
      `STATE_CHANGE time=${new Date().toISOString()} ` +
      `state=${success ? 'RECOVERED' : 'FAILED'}`
    );
  }

  if (success && consecutiveSuccesses === 5) {
    console.log(
      `STABLE_CHECK time=${new Date().toISOString()} ` +
      `five_consecutive_successes=true`
    );
  }

  previousSuccess = success;
  sleep(0.2);
}
