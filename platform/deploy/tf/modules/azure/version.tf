# The release of ROKOLabs/platform this module deploys. Held in both provider
# modules and checked against the tag by CI, so `modules/aws` and `modules/azure`
# can never publish a release that deploys different images.
locals {
  platform_version = "0.0.13"
}
