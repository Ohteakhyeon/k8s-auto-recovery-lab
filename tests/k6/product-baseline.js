
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const productFailureRate = new Rate('product_failure_rate');

export const options = {
  vus: 1,
  duration: '30s',
};

export default function () {
  const response = http.get('http://localhost:8080/');

  const success = check(response, {
    'HTTP 200': (r) => r.status === 200,
    '상품 목록 표시': (r) =>
      r.body !== null &&
      r.body.includes('Hot Products') &&
      r.body.includes('Sunglasses'),
  });

  productFailureRate.add(!success);

  if (!success) {
    console.log(
      `FAIL time=${new Date().toISOString()} status=${response.status}`
    );
  }

  sleep(0.5);
}
