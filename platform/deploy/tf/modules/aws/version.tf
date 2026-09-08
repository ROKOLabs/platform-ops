# The release of ROKOLabs/platform this module deploys.
#
# It resolves three things at once: the chart version pulled from
# oci://registry-1.docker.io/rokoplatform, the docker.io/rokoplatform/* image
# tag the chart runs, and the tag a deployment pins with `?ref=`.
#
# CI refuses a tag that disagrees with this constant, so a deployment pinned at
# `?ref=X.Y.Z` can never get the infrastructure of one release and the images of
# another. Changing this value and pushing the matching tag is what a release is.
locals {
  platform_version = "0.0.13"
}
