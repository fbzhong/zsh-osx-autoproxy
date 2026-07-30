#!/usr/bin/env bash

set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$test_dir/proxy_test.sh"
