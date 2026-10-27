
import grpc from 'k6/net/grpc';
import { check, sleep } from 'k6';

const client = new grpc.Client();
client.load(['.'], 'demo.proto');

export const options = {
  vus: 10,
  duration: '60s',
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

  check(response, {
    'gRPC request OK': (r) => r.status === grpc.StatusOK,
  });

  client.close();
  sleep(0.1);
}
