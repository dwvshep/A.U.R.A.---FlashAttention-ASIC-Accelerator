#!/usr/bin/env python3
#pip install torch transformers numpy

import torch
import numpy as np
import argparse
import os
from transformers import AutoTokenizer, AutoModel

# -----------------------------
# Argument parser
# -----------------------------
parser = argparse.ArgumentParser(description="Generate Q/K/V mem files for AURA ASIC.")
parser.add_argument("--model", type=str, default="bert-base-uncased",
                    help="Transformer model name (default: bert-base-uncased)")
parser.add_argument("--seq", type=int, default=512,
                    help="Sequence length (default: 512)")
parser.add_argument("--head", type=int, default=0,
                    help="Attention head index (default: 0)")
args = parser.parse_args()

MODEL_NAME = args.model
SEQ_LEN = args.seq
HEAD_IDX = args.head

OUT_DIR = f"models/{TEST}"
os.makedirs(OUT_DIR, exist_ok=True)

OUTPUT_FILES = [
    f"{OUT_DIR}/Q.mem",
    f"{OUT_DIR}/K.mem",
    f"{OUT_DIR}/V.mem"
]

print(f"[INFO] Generating Q/K/V for test '{MODEL_NAME}' into directory: {OUT_DIR}")
print(f"[INFO] Model: {MODEL_NAME}, Seq Len: {SEQ_LEN}, Head: {HEAD_IDX}")

# -----------------------------
# Helper: write FP32 values as hex
# -----------------------------
def write_mem_file(matrix, filename):
    with open(filename, "w") as f:
        for row in matrix:
            for i, val in enumerate(row):
                hex_val = np.float32(val).tobytes().hex().upper()
                f.write(hex_val)
                if (i+1) % 8 == 0:
                    f.write("\n")
            if len(row) % 8 != 0:
                f.write("\n")

# -----------------------------
# Load tokenizer + model
# -----------------------------
print("[INFO] Loading model and tokenizer...")
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
model = AutoModel.from_pretrained(MODEL_NAME, output_attentions=True)
model.eval()

# -----------------------------
# Input text: generate enough tokens
# -----------------------------
text = " ".join(["Are you sure this is changing??"] * SEQ_LEN)

tokens = tokenizer(text, return_tensors="pt",
                   padding="max_length",
                   truncation=True,
                   max_length=SEQ_LEN)

input_ids = tokens["input_ids"]

# -----------------------------
# Extract Q/K/V from first encoder layer
# -----------------------------
attn_layer = model.encoder.layer[0].attention.self

def extract_qkv(x):
    B, T, H = x.shape
    head_dim = attn_layer.query.out_features // attn_layer.num_attention_heads

    Q = attn_layer.query(x).view(B, T, attn_layer.num_attention_heads, head_dim)
    K = attn_layer.key(x).view(B, T, attn_layer.num_attention_heads, head_dim)
    V = attn_layer.value(x).view(B, T, attn_layer.num_attention_heads, head_dim)
    return Q, K, V

print("[INFO] Running model forward pass...")
with torch.no_grad():
    embeddings = model.embeddings(input_ids)
    Q, K, V = extract_qkv(embeddings)

# Choose head
Q = Q[0, :, HEAD_IDX, :].cpu().numpy()  # shape [seq_len, head_dim]
K = K[0, :, HEAD_IDX, :].cpu().numpy()
V = V[0, :, HEAD_IDX, :].cpu().numpy()

# -----------------------------
# Write files
# -----------------------------
print("[INFO] Writing Q/K/V memory files...")

write_mem_file(Q, OUTPUT_FILES[0])
write_mem_file(K, OUTPUT_FILES[1])
write_mem_file(V, OUTPUT_FILES[2])

print("[SUCCESS] Done!")
print("Generated files:")
for f in OUTPUT_FILES:
    print("  -", f)
