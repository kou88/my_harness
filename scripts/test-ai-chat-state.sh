#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
# A unique executable name isolates UserDefaults from the real app and tests.
xcrun swiftc -parse-as-library MyHarness/domain/ai/AIModels.swift \
  MyHarness/state/AIChatState.state.swift Tests/AIChatStateRegression/ControlledTransport.swift \
  Tests/AIChatStateRegression/SessionRegression.swift \
  -o "$test_dir/ai-chat-regression-$(uuidgen)"
python3 - "$test_dir" <<'PY'
import pathlib, subprocess, sys
binary, = pathlib.Path(sys.argv[1]).glob('ai-chat-regression-*')
subprocess.run([str(binary)], check=True, timeout=20)
PY
