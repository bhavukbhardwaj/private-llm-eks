#!/usr/bin/env bash
# Runs ON THE BASTION. Sends one question to the model through the internal ALB and prints only the answer.
# Usage: ~/k8s/ask.sh "your question"        env: MAX_TOKENS (default 150)
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck disable=SC1091
source ./config.env
QUESTION="${1:?usage: ask.sh \"your question\"}"
HOST="$(kubectl -n llm get ingress vllm -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
BODY="$(QUESTION="$QUESTION" MODEL_NAME="$MODEL_NAME" MAX_TOKENS="${MAX_TOKENS:-150}" python3 -c '
import json, os
print(json.dumps({"model": os.environ["MODEL_NAME"], "messages": [{"role": "user", "content": os.environ["QUESTION"]}], "max_tokens": int(os.environ["MAX_TOKENS"])}))')"
curl -fsS -m 60 "http://${HOST}/v1/chat/completions" -H 'Content-Type: application/json' -d "$BODY" \
  | python3 -c 'import sys, json; r = json.load(sys.stdin); print(r["choices"][0]["message"]["content"]); print("[tokens: %d prompt, %d completion]" % (r["usage"]["prompt_tokens"], r["usage"]["completion_tokens"]))'
