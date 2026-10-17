"""Sends N chat-completion requests at a fixed concurrency and prints throughput, p50/p95 latency and errors as JSON."""
import argparse
import json
import statistics
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor


def one_request(url, model, prompt, max_tokens, timeout):
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
    }).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    start = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.load(resp)
        tokens = data.get("usage", {}).get("completion_tokens", 0)
        return time.perf_counter() - start, tokens, None
    except Exception as exc:  # network errors, HTTP errors, timeouts
        return time.perf_counter() - start, 0, f"{type(exc).__name__}: {exc}"


def percentile(values, pct):
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(round(pct / 100 * (len(ordered) - 1))))]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--url", required=True, help="e.g. http://<internal-alb>/v1/chat/completions")
    p.add_argument("--model", default="qwen2.5-7b-instruct")
    p.add_argument("--requests", type=int, default=200)
    p.add_argument("--concurrency", type=int, default=4)
    p.add_argument("--max-tokens", type=int, default=128)
    p.add_argument("--prompt", default="Explain in two sentences why private networking matters for confidential documents.")
    p.add_argument("--timeout", type=float, default=120)
    a = p.parse_args()

    start = time.perf_counter()
    with ThreadPoolExecutor(max_workers=a.concurrency) as pool:
        results = list(pool.map(lambda _: one_request(a.url, a.model, a.prompt, a.max_tokens, a.timeout), range(a.requests)))
    elapsed = time.perf_counter() - start

    ok = [r for r in results if r[2] is None]
    errors = [r[2] for r in results if r[2] is not None]
    latencies = [r[0] for r in ok]
    print(json.dumps({
        "model": a.model,
        "requests": a.requests,
        "concurrency": a.concurrency,
        "duration_s": round(elapsed, 2),
        "throughput_req_per_s": round(len(ok) / elapsed, 3),
        "output_tokens_per_s": round(sum(r[1] for r in ok) / elapsed, 2),
        "latency_p50_s": round(percentile(latencies, 50), 3) if latencies else None,
        "latency_p95_s": round(percentile(latencies, 95), 3) if latencies else None,
        "latency_mean_s": round(statistics.mean(latencies), 3) if latencies else None,
        "errors": len(errors),
        "error_samples": sorted(set(errors))[:3],
    }, indent=2))


if __name__ == "__main__":
    main()
