# Wan2.1-T2V-1.3B baseline benchmarking lab (vLLM-Omni)
# Workflow: make setup -> make start -> make smoke -> make baseline

SERVER_SESSION ?= wan21-server

.PHONY: help setup start stop smoke baseline benchmark clean-logs logs env

help:
	@echo "Targets:"
	@echo "  make setup      - install system deps, venv, vLLM+vLLM-Omni, model, capture environment"
	@echo "  make start      - start vLLM-Omni server in tmux (port 8091)"
	@echo "  make stop       - stop the server"
	@echo "  make smoke      - run smoke test (1 request, ffprobe validation)"
	@echo "  make baseline   - run the baseline benchmark (1 warmup + 5 measured)"
	@echo "  make benchmark  - alias: smoke then baseline"
	@echo "  make logs       - tail the server log"
	@echo "  make clean-logs - delete log files (never touches results/outputs)"

setup:
	bash scripts/setup.sh

start:
	bash scripts/start_server.sh

stop:
	bash scripts/stop_server.sh

smoke:
	bash scripts/smoke_test.sh

baseline:
	bash scripts/baseline.sh

benchmark:
	bash scripts/benchmark.sh

logs:
	tail -f logs/server.log

clean-logs:
	rm -f logs/*.log
	@echo "logs cleaned (results/ and outputs/ untouched)"

env:
	@cat benchmarks/config/environment.json
