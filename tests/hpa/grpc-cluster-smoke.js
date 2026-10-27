
import grpc from 'k6/net/grpc';
import { check } from 'k6';

const client = new grpc.Client();
client.load(['.'], 'demo.proto');

export const options = {
  vus: 1,
  iterations: 1,
  thresholds: {
    checks: ['rate==1'],
  },
};

export default function () {
  client.connect('productcatalog-hpa.recovery-test.svc.cluster.local:3550', {
    plaintext: true,
    timeout: '10s',
  });

  const response = client.invoke(
    'hipstershop.ProductCatalogService/ListProducts',
    {}
  );

  check(response, {
    'gRPC request OK': (r) => r.status === grpc.StatusOK,
    'products returned': (r) =>
      Array.isArray(r.message?.products) &&
      r.message.products.length > 0,
  });

  client.close();
}
