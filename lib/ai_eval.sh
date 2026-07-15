#!/usr/bin/env bash

OTAI_MODELS_DIR="/opt/open-ticket-ai/models"
OTAI_EVAL_DIR="/opt/open-ticket-ai/evaluation"
OTAI_EVAL_RESULTS="${OTAI_EVAL_DIR}/results.json"

evaluate_model_accuracy() {
	local model_path="$1"
	local model_name="$2"
	local test_data="${3:-/opt/open-ticket-ai/training/val.jsonl}"

	info "Evaluating accuracy of model $model_name..."

	mkdir -p "$OTAI_EVAL_DIR"

	if [ ! -f "$test_data" ]; then
		warn "Test data not found at $test_data"
		register_result "EvalAccuracy" "SKIP" "No test data available"
		return
	fi

	local eval_result
	eval_result=$(
		sudo -u "$OTAI_USER" python3 <<PYTHON 2>/dev/null
import json, os, sys, time
from transformers import AutoTokenizer, AutoModelForSequenceClassification
import torch
import numpy as np

model_path = '$model_path'
model_name_str = '$model_name'
test_file = '$test_data'

try:
    tokenizer = AutoTokenizer.from_pretrained(model_path)
    model = AutoModelForSequenceClassification.from_pretrained(model_path)
except Exception as e:
    print(json.dumps({'model': model_name_str, 'error': str(e)}))
    sys.exit(1)

with open(test_file) as f:
    samples = [json.loads(line) for line in f if line.strip()]

if not samples:
    print(json.dumps({'model': model_name_str, 'error': 'no test samples'}))
    sys.exit(0)

correct = 0
total = 0
inference_times = []
label_map = {v: k for k, v in model.config.label2id.items()} if hasattr(model.config, 'label2id') else {}

for s in samples:
    inputs = tokenizer(s['text'], return_tensors='pt', truncation=True, padding=True, max_length=128)
    start = time.time()
    with torch.no_grad():
        outputs = model(**inputs)
    elapsed = time.time() - start
    inference_times.append(elapsed)

    pred_id = torch.argmax(outputs.logits, dim=1).item()
    pred_label = label_map.get(pred_id, str(pred_id))
    true_label = s.get('label', '')
    if pred_label == true_label:
        correct += 1
    total += 1

accuracy = correct / total if total > 0 else 0
avg_time = sum(inference_times) / len(inference_times) if inference_times else 0
throughput = 1.0 / avg_time if avg_time > 0 else 0

result = {
    'model': model_name_str,
    'accuracy': round(accuracy, 4),
    'samples': total,
    'correct': correct,
    'avg_inference_ms': round(avg_time * 1000, 2),
    'throughput_sec': round(throughput, 2),
}

print(json.dumps(result))
PYTHON
	) || {
		warn "Evaluation script failed for $model_name"
		return 1
	}
	echo "$eval_result" >"${OTAI_EVAL_DIR}/results_${model_name}.json"
	register_result "Eval_${model_name}" "OK" "Accuracy evaluated"
}

benchmark_model_speed() {
	local model_path="$1"
	local model_name="$2"
	local iterations="${3:-100}"

	info "Benchmarking speed of model $model_name ($iterations iterations)..."

	local bench_result
	bench_result=$(
		sudo -u "$OTAI_USER" python3 <<PYTHON 2>/dev/null
import json, sys, time
from transformers import AutoTokenizer, AutoModelForSequenceClassification
import torch

model_path = '$model_path'
model_name_str = '$model_name'
iterations = $iterations

tokenizer = AutoTokenizer.from_pretrained(model_path)
model = AutoModelForSequenceClassification.from_pretrained(model_path)
model.eval()

text = "This is a sample ticket about a network issue with the mail server in the accounting department."
inputs = tokenizer(text, return_tensors='pt', truncation=True, padding=True, max_length=128)

warmup = 10
for _ in range(warmup):
    with torch.no_grad():
        model(**inputs)

torch.cuda.synchronize() if torch.cuda.is_available() else None

times = []
for _ in range(iterations):
    start = time.time()
    with torch.no_grad():
        model(**inputs)
    torch.cuda.synchronize() if torch.cuda.is_available() else None
    times.append(time.time() - start)

avg_ms = (sum(times) / len(times)) * 1000

import os
mem_mb = 0
try:
    import psutil
    proc = psutil.Process(os.getpid())
    mem_mb = proc.memory_info().rss / (1024 * 1024)
except Exception:
    pass

result = {
    'model': model_name_str,
    'avg_inference_ms': round(avg_ms, 2),
    'iterations': iterations,
    'memory_mb': round(mem_mb, 1),
}

print(json.dumps(result))
PYTHON
	) || {
		warn "Benchmark script failed for $model_name"
		return 1
	}
	echo "$bench_result" >"${OTAI_EVAL_DIR}/results_${model_name}.json"
	register_result "Benchmark_${model_name}" "OK" "Speed benchmark completed"
}

compare_models() {
	mkdir -p "$OTAI_EVAL_DIR"

	local results=()
	local model_dirs=()

	for d in "$OTAI_MODELS_DIR"/*/; do
		[ -d "$d" ] || continue
		local name
		name=$(basename "$d")
		model_dirs+=("$d")
		if [ -f "${d}/config.json" ]; then
			results+=("$name")
		fi
	done

	if [ ${#results[@]} -eq 0 ]; then
		warn "No trained models found to compare"
		register_result "ModelCompare" "INFO" "No models to compare"
		return
	fi

	for name in "${results[@]}"; do
		local d="$OTAI_MODELS_DIR/$name"
		evaluate_model_accuracy "$d" "$name"
		benchmark_model_speed "$d" "$name" 50
	done

	# Generate comparison report
	python3 -c "
import json, os, glob

eval_dir = '$OTAI_EVAL_DIR'
results = {}

for f in glob.glob(os.path.join(eval_dir, 'results_*.json')):
    with open(f) as fh:
        data = json.load(fh)
        results[data['model']] = data

with open('$OTAI_EVAL_RESULTS', 'w') as f:
    json.dump(results, f, indent=2)

print('Model Comparison:')
print('='*70)
print(f\"{'Model':<20} {'Accuracy':<12} {'Latency(ms)':<12} {'Throughput/s':<12} {'Memory(MB)':<12}\")
print('-'*70)
for name, r in sorted(results.items()):
    acc = f\"{r.get('accuracy', 0)*100:.1f}%\" if 'accuracy' in r else '--'
    lat = f\"{r.get('avg_inference_ms', 0):.1f}\"
    thr = f\"{r.get('throughput_sec', 0):.1f}\"
    mem = f\"{r.get('memory_mb', 0):.0f}\"
    print(f\"{name:<20} {acc:<12} {lat:<12} {thr:<12} {mem:<12}\")
print('='*70)
" 2>/dev/null || warn "Comparison report generation failed"

	register_result "ModelCompare" "OK" "All models compared"
}

run_evaluation() {
	echo ""
	echo "========================================"
	echo "  AI Model Evaluation"
	echo "========================================"
	echo "  1) Evaluate a single model"
	echo "  2) Benchmark speed of a model"
	echo "  3) Compare all installed models"
	echo "  4) Back"
	echo "========================================"

	local choice
	read -r -p "Select option: " choice
	case "$choice" in
	1)
		echo ""
		echo "Available models:"
		local i=1
		local models=()
		for d in "$OTAI_MODELS_DIR"/*/; do
			[ -d "$d" ] || continue
			local name
			name=$(basename "$d")
			echo "  $i) $name"
			models+=("$name")
			((i++))
		done
		read -r -p "Select model: " m
		local idx=$((m - 1))
		if [ "$idx" -ge 0 ] && [ "$idx" -lt ${#models[@]} ]; then
			evaluate_model_accuracy "${OTAI_MODELS_DIR}/${models[$idx]}" "${models[$idx]}"
		fi
		;;
	2)
		echo ""
		echo "Available models:"
		local i=1
		local models=()
		for d in "$OTAI_MODELS_DIR"/*/; do
			[ -d "$d" ] || continue
			local name
			name=$(basename "$d")
			echo "  $i) $name"
			models+=("$name")
			((i++))
		done
		read -r -p "Select model: " m
		local idx=$((m - 1))
		if [ "$idx" -ge 0 ] && [ "$idx" -lt ${#models[@]} ]; then
			benchmark_model_speed "${OTAI_MODELS_DIR}/${models[$idx]}" "${models[$idx]}"
		fi
		;;
	3)
		compare_models
		;;
	4) return ;;
	*) warn "Invalid option" ;;
	esac

	echo ""
	if [ -f "$OTAI_EVAL_RESULTS" ]; then
		echo "Full results: $OTAI_EVAL_RESULTS"
	fi
}
