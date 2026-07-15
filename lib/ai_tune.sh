#!/usr/bin/env bash

OTAI_TUNE_DIR="/opt/open-ticket-ai/training"
OTAI_MODELS_DIR="/opt/open-ticket-ai/models"
OTAI_FINE_TUNED_DIR="${OTAI_MODELS_DIR}/fine-tuned"
OTAI_TRAIN_DATA="${OTAI_TUNE_DIR}/train.jsonl"
OTAI_VAL_DATA="${OTAI_TUNE_DIR}/val.jsonl"

# shellcheck source=lib/ai.sh
source "$(dirname "${BASH_SOURCE[0]}")/ai.sh"

export_tickets_for_training() {
	local otobo_root="${1:-/opt/otobo}"
	local otobo_user="${2:-otobo}"
	local days_back="${3:-30}"
	local limit="${4:-1000}"

	info "Exporting tickets from OTOBO (last $days_back days, max $limit)..."

	mkdir -p "$OTAI_TUNE_DIR"
	chown "${OTAI_USER}:${OTAI_GROUP}" "$OTAI_TUNE_DIR"

	cd "$otobo_root" || die "Cannot cd to $otobo_root"

	# shellcheck disable=SC2024
	sudo -u "$otobo_user" perl bin/otobo.Console.pl Maint::Ticket::Search \
		"--limit" "$limit" \
		"--created-after" "$(date -d "$days_back days ago" '+%Y-%m-%d')" \
		"--output" "json" 2>/dev/null >"${OTAI_TUNE_DIR}/tickets_raw.json"
	# shellcheck disable=SC2181
	if [ $? -ne 0 ]; then
		warn "Console.pl export failed, falling back to DB export"
		export_tickets_from_db "$otobo_root"
		return
	fi

	register_result "TicketExport" "OK" "Exported up to $limit tickets from last $days_back days"
}

export_tickets_from_db() {
	local otobo_root="${1:-/opt/otobo}"
	local db_engine="${DB_ENGINE:-mariadb}"
	local db_name="${DB_NAME:-otobo}"
	local db_user="${DB_USER:-otobo}"
	local db_pass="${DB_PASS:-}"

	info "Exporting tickets directly from database..."

	if [ "$db_engine" = "postgresql" ]; then
		PGPASSWORD="$db_pass" psql -U "$db_user" -d "$db_name" -t -A \
			-F $'\t' \
			-c "SELECT t.id, t.tn, t.title, q.name AS queue, t.create_time_unix
			    FROM ticket t JOIN queue q ON t.queue_id = q.id
			    ORDER BY t.create_time_unix DESC LIMIT 1000" \
			2>/dev/null >"${OTAI_TUNE_DIR}/tickets_raw.tsv"
	else
		mysql -u "$db_user" -p"$db_pass" "$db_name" \
			-e "SELECT t.id, t.tn, t.title, q.name AS queue, t.create_time_unix
			    FROM ticket t JOIN queue q ON t.queue_id = q.id
			    ORDER BY t.create_time_unix DESC LIMIT 1000" \
			-B 2>/dev/null >"${OTAI_TUNE_DIR}/tickets_raw.tsv"
	fi

	register_result "TicketExport" "OK" "Exported tickets from database"
}

prepare_training_data() {
	info "Preparing training data for fine-tuning..."

	mkdir -p "$OTAI_TUNE_DIR"

	local raw_file="${OTAI_TUNE_DIR}/tickets_raw.json"
	local tsv_file="${OTAI_TUNE_DIR}/tickets_raw.tsv"

	if [ -f "$raw_file" ]; then
		python3 -c "
import json, sys

tickets = json.load(open('$raw_file'))
with open('$OTAI_TRAIN_DATA', 'w') as train, open('$OTAI_VAL_DATA', 'w') as val:
    for i, t in enumerate(tickets[:800]):
        text = f\"{t.get('title', '')} {t.get('body', '')}\"
        label = t.get('queue', 'Raw')
        train.write(json.dumps({'text': text, 'label': label}) + '\n')
    for i, t in enumerate(tickets[800:1000]):
        text = f\"{t.get('title', '')} {t.get('body', '')}\"
        label = t.get('queue', 'Raw')
        val.write(json.dumps({'text': text, 'label': label}) + '\n')
" 2>/dev/null || warn "Failed to prepare training data from JSON"
	elif [ -f "$tsv_file" ]; then
		python3 -c "
import csv, json

with open('$tsv_file') as f:
    reader = csv.DictReader(f, delimiter='\t')
    rows = list(reader)
with open('$OTAI_TRAIN_DATA', 'w') as train, open('$OTAI_VAL_DATA', 'w') as val:
    for i, r in enumerate(rows[:800]):
        train.write(json.dumps({'text': r.get('title', ''), 'label': r.get('queue', 'Raw')}) + '\n')
    for i, r in enumerate(rows[800:1000]):
        val.write(json.dumps({'text': r.get('title', ''), 'label': r.get('queue', 'Raw')}) + '\n')
" 2>/dev/null || warn "Failed to prepare training data from TSV"
	else
		warn "No ticket data found to prepare"
		return 1
	fi

	chown -R "${OTAI_USER}:${OTAI_GROUP}" "$OTAI_TUNE_DIR"
	register_result "TrainData" "OK" "Training/validation data prepared ($OTAI_TRAIN_DATA)"
}

fine_tune_model() {
	local base_model="${1:-sentence-transformers/all-MiniLM-L6-v2}"
	local output_dir="${2:-$OTAI_FINE_TUNED_DIR}"
	local epochs="${3:-3}"
	local batch_size="${4:-8}"

	info "Fine-tuning model $base_model for $epochs epochs..."

	if [ ! -f "$OTAI_TRAIN_DATA" ]; then
		warn "Training data not found at $OTAI_TRAIN_DATA"
		prepare_training_data || die "Cannot prepare training data"
	fi

	mkdir -p "$output_dir"

	sudo -u "$OTAI_USER" python3 <<PYTHON 2>/dev/null
import json, os
from datasets import Dataset, DatasetDict
from transformers import (
    AutoTokenizer, AutoModelForSequenceClassification,
    Trainer, TrainingArguments, EarlyStoppingCallback
)
import numpy as np

train_texts, train_labels, val_texts, val_labels = [], [], [], []
label_set = set()

for path, texts, labels in [('$OTAI_TRAIN_DATA', train_texts, train_labels),
                              ('$OTAI_VAL_DATA', val_texts, val_labels)]:
    with open(path) as f:
        for line in f:
            d = json.loads(line)
            texts.append(d['text'])
            labels.append(d['label'])
            label_set.add(d['label'])

label_list = sorted(label_set)
label2id = {l: i for i, l in enumerate(label_list)}
id2label = {i: l for l, i in label2id.items()}

def encode(examples):
    return tokenizer(examples['text'], truncation=True, padding='max_length', max_length=128)

tokenizer = AutoTokenizer.from_pretrained('$base_model')

train_ds = Dataset.from_dict({
    'text': train_texts,
    'label': [label2id[l] for l in train_labels]
})
val_ds = Dataset.from_dict({
    'text': val_texts,
    'label': [label2id[l] for l in val_labels]
})

train_ds = train_ds.map(encode, batched=True)
val_ds = val_ds.map(encode, batched=True)

model = AutoModelForSequenceClassification.from_pretrained(
    '$base_model',
    num_labels=len(label_list),
    label2id=label2id,
    id2label=id2label
)

args = TrainingArguments(
    output_dir='$output_dir',
    evaluation_strategy='epoch',
    save_strategy='epoch',
    learning_rate=2e-5,
    per_device_train_batch_size=$batch_size,
    per_device_eval_batch_size=$batch_size,
    num_train_epochs=$epochs,
    weight_decay=0.01,
    load_best_model_at_end=True,
    push_to_hub=False,
)

trainer = Trainer(
    model=model,
    args=args,
    train_dataset=train_ds,
    eval_dataset=val_ds,
    callbacks=[EarlyStoppingCallback(early_stopping_patience=2)],
)

trainer.train()
trainer.save_model('$output_dir')
tokenizer.save_pretrained('$output_dir')

with open(os.path.join('$output_dir', 'label2id.json'), 'w') as f:
    json.dump(label2id, f)
with open(os.path.join('$output_dir', 'training_config.json'), 'w') as f:
    json.dump({'base_model': '$base_model', 'epochs': $epochs, 'batch_size': $batch_size}, f)

print("Fine-tuning complete")
PYTHON
	# shellcheck disable=SC2181
	if [ $? -ne 0 ]; then
		warn "Fine-tuning script failed"
		register_result "FineTune" "FAIL" "Training failed — check Python dependencies"
		return 1
	fi

	if [ -f "${output_dir}/config.json" ]; then
		chown -R "${OTAI_USER}:${OTAI_GROUP}" "$output_dir"
		register_result "FineTune" "OK" "Model fine-tuned and saved to $output_dir"
	else
		register_result "FineTune" "FAIL" "Fine-tuning produced no output"
		return 1
	fi
}

update_config_for_tuned_model() {
	info "Updating OTAI config to use fine-tuned model..."

	if [ ! -f "$OTAI_CONFIG_FILE" ]; then
		warn "OTAI config not found at $OTAI_CONFIG_FILE"
		return 1
	fi

	sed -i "s|model:.*|model: \"${OTAI_FINE_TUNED_DIR}\"|" "$OTAI_CONFIG_FILE"
	chown "${OTAI_USER}:${OTAI_GROUP}" "$OTAI_CONFIG_FILE"

	register_result "ConfigUpdate" "OK" "OTAI config now points to fine-tuned model"
}

restart_otai_after_tune() {
	info "Restarting Open Ticket AI service..."

	if systemctl is-enabled open-ticket-ai.service 2>/dev/null | grep -q enabled; then
		systemctl restart open-ticket-ai.service
		register_result "OTAIRestart" "OK" "Open Ticket AI restarted with fine-tuned model"
	else
		warn "Open Ticket AI service not found"
	fi
}

run_fine_tuning_pipeline() {
	local otobo_root="${1:-/opt/otobo}"
	local otobo_user="${2:-otobo}"

	echo ""
	echo "========================================"
	echo "  AI Fine-Tuning Pipeline"
	echo "========================================"

	local days
	days=$(prompt_with_default "Export tickets from last N days" "90")
	local epochs
	epochs=$(prompt_with_default "Training epochs" "3")

	export_tickets_for_training "$otobo_root" "$otobo_user" "$days"
	prepare_training_data
	fine_tune_model "sentence-transformers/all-MiniLM-L6-v2" "$OTAI_FINE_TUNED_DIR" "$epochs"
	update_config_for_tuned_model
	restart_otai_after_tune

	echo ""
	echo "========================================"
	echo "  Fine-Tuning Complete"
	echo "========================================"
	echo "  Model:    $OTAI_FINE_TUNED_DIR"
	echo "  Config:   $OTAI_CONFIG_FILE"
	echo "========================================"
}
