# Copyright 2026 Han Li and contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# A throwaway Ubuntu with vfox installed, for running tests/e2e/linux/e2e.sh
# locally. The checkout is mounted at run time, not copied in:
#   docker build -t zig-e2e tests/e2e/linux
#   docker run --rm -v "$PWD:/src:ro" zig-e2e
FROM ubuntu:26.04

# A failing step in a pipe fails the build.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Pinned like .github/workflows/test.yml: the release and its SHA-256, which is
# the digest GitHub lists for the asset. vfox 1.1.0 or later has the Detect hook.
ARG VFOX_VERSION=1.1.0
ARG VFOX_SHA256=3b33c3c468b27bc17aecf0d6d3af24fe49fe204972984904a136a47b402a0ee4

# The base image is pinned by its tag, and a throwaway test image takes the
# current Ubuntu packages, so the package versions are not pinned.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates curl tar xz-utils zip unzip \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    archive=/tmp/vfox.tar.gz; \
    curl --fail --silent --show-error --location --retry 3 --output "$archive" \
        "https://github.com/version-fox/vfox/releases/download/v${VFOX_VERSION}/vfox_${VFOX_VERSION}_linux_x86_64.tar.gz"; \
    echo "$VFOX_SHA256  $archive" | sha256sum --check; \
    tar --extract --gzip --file "$archive" --directory /usr/local/bin --strip-components=1 \
        "vfox_${VFOX_VERSION}_linux_x86_64/vfox"; \
    rm "$archive"

WORKDIR /work
CMD ["bash", "/src/tests/e2e/linux/e2e.sh"]
