# Object Storage Verification

Sample scripts to test and verify different object storage implementations using plain [curl](https://curl.se/).

## OpenStack Object Storage (Swift)

Mandatory variables:

```shell
export SWIFT_IP=1.2.3.4
export SWIFT_USER=myuser
export SWIFT_PASSWORD=mypassword
export SWIFT_PROJECT=myproject
./swiftcurl.sh
```

Optional variables:

```shell
export SWIFT_PROTOCOL=http
export SWIFT_AUTH_PORT=5000
export SWIFT_STORAGE_PORT=8080
export SWIFT_CONTAINER=swiftcurl_test
export SWIFT_POLICY=policy-0
./swiftcurl.sh
```

Reference documentation:

- [API Examples using Curl](https://docs.openstack.org/keystone/train/api_curl_examples.html)
- [Object Storage API](https://docs.openstack.org/api-ref/object-store/index.html)

## S3

Reference documentation:

- [Amazon S3 REST API with curl](https://czak.pl/2015/09/15/s3-rest-api-with-curl.html)

## Copyright & License

Copyright IBM Corporation 2023, released under the terms of the [Apache License 2.0](LICENSE).
