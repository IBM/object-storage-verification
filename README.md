# Object Storage Verification

Sample scripts to test and verify different object storage implementations using plain [curl](https://curl.se/).

## OpenStack Object Storage (Swift)

```shell
export SWIFT_IP=1.2.3.4
export SWIFT_USER=myuser
export SWIFT_PASSWORD=mypassword
export SWIFT_PROJECT=myproject
./swiftcurl.sh
```
