
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
  client.connect('127.0.0.1:3550', {
    plaintext: true,
    timeout: '10s',
  });

  const response = client.invoke(
    'hipstershop.ProductCatalogService/ListProducts',
    {}
  );

  const success = check(response, {
    'gRPC status OK': (r) => r.status === grpc.StatusOK,
    'products returned': (r) =>
      Array.isArray(r.message?.products) &&
      r.message.products.length > 0,
  });

  console.log(
    `status=${response.status}, products=${response.message?.products?.length ?? 0}`
  );

  if (!success) {
    console.error(JSON.stringify(response));
  }

  client.close();
}
