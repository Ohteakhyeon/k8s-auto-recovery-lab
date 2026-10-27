import grpc from 'k6/net/grpc';
import { check } from 'k6';

const client = new grpc.Client();
client.load(['.'], 'demo.proto');

export const options = {
  scenarios: {
    productcatalog_load: {
      executor: 'constant-arrival-rate',
      rate: 100,
      timeUnit: '1s',
      duration: '3m',
      preAllocatedVUs: 20,
      maxVUs: 40,
    },
  },
};

export default function () {
  if (__ITER === 0) {
    client.connect(
      'productcatalog-hpa.recovery-test.svc.cluster.local:3550',
      {
        plaintext: true,
        timeout: '10s',
      }
    );
  }

  const response = client.invoke(
    'hipstershop.ProductCatalogService/ListProducts',
    {}
  );

  check(response, {
    'gRPC request OK': (r) =>
      r && r.status === grpc.StatusOK,
  });
}