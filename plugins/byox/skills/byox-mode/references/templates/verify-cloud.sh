#!/bin/sh
# Verify a cloud or DevOps step the way boot.dev does: run the real CLI and check what
# it says. Copy it to course/verify/<step>.sh and replace the checks. Each check prints
# a tick or a cross, and the first cross stops the script with a readable reason.
# The AWS CLI reads AWS_ENDPOINT_URL, so the same script runs against real AWS or a
# local emulator such as Floci (http://localhost:4566) with no change.
set -u

check() { # check "what should be true" command args...
  label=$1; shift
  if out=$("$@" 2>&1); then
    echo "  ok   $label"
  else
    echo "  FAIL $label"
    echo "       command: $*"
    echo "$out" | head -n 5 | sed 's/^/       /'
    exit 1
  fi
}

check_out() { # check_out "what should be true" "expected output" command args...
  label=$1; expected=$2; shift 2
  actual=$("$@" 2>&1 | tr -d '\r' | sed 's/[[:space:]]*$//')
  if [ "$actual" = "$expected" ]; then
    echo "  ok   $label"
  else
    echo "  FAIL $label"
    echo "       command:  $*"
    echo "       expected: $expected"
    echo "       got:      $actual"
    exit 1
  fi
}

BUCKET=corsego-uploads

check     "the bucket $BUCKET exists"            aws s3api head-bucket --bucket "$BUCKET"
check_out "versioning is enabled on the bucket"  "Enabled" aws s3api get-bucket-versioning --bucket "$BUCKET" --query Status --output text
echo "All checks passed."
