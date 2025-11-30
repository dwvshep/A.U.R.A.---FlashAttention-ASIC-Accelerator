#pip install torch transformers numpy

import os
import sys
import torch
import numpy as np
from transformers import AutoTokenizer, AutoModel

# -----------------------------
# Parameters
# -----------------------------
MODEL_NAME = "bert-base-uncased"
SEQ_LEN = 512         # number of tokens = rows
HEAD_IDX = 0          # which attention head to extract

# -----------------------------
# Parse directory argument
# -----------------------------
if len(sys.argv) < 2:
    print("Usage: python extract_qkv.py <directory_name>")
    sys.exit(1)

dir_name = sys.argv[1]
out_dir = os.path.join("../mem", dir_name)
os.makedirs(out_dir, exist_ok=True)

OUTPUT_FILES = [
    os.path.join(out_dir, "Q_32.mem"),
    os.path.join(out_dir, "K_32.mem"),
    os.path.join(out_dir, "V_32.mem"),
]

# -----------------------------
# Sample input text (enough to generate 512 tokens)
# -----------------------------
text = " ".join(["Are you sure this is changing??"] * 512)  # repeat so tokenizer produces 512 tokens

# -----------------------------
# Load model
# -----------------------------
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
model = AutoModel.from_pretrained(MODEL_NAME, output_attentions=True)
model.eval()

tokens = tokenizer(text, return_tensors="pt", padding="max_length", truncation=True, max_length=SEQ_LEN)
input_ids = tokens["input_ids"]

# -----------------------------
# Extract Q/K/V from first attention layer
# -----------------------------
attn_layer = model.encoder.layer[0].attention.self

def forward_hook_forward(x):
    B, T, H = x.shape[0], x.shape[1], attn_layer.query.out_features
    Q = attn_layer.query(x).view(B, T, attn_layer.num_attention_heads, -1)
    K = attn_layer.key(x).view(B, T, attn_layer.num_attention_heads, -1)
    V = attn_layer.value(x).view(B, T, attn_layer.num_attention_heads, -1)
    return Q, K, V

with torch.no_grad():
    embeddings = model.embeddings(input_ids)
    Q, K, V = forward_hook_forward(embeddings)

# Select head 0
Q = Q[0, :, HEAD_IDX, :].cpu().numpy()   # shape [512, 64]
K = K[0, :, HEAD_IDX, :].cpu().numpy()
V = V[0, :, HEAD_IDX, :].cpu().numpy()

# -----------------------------
# Helper to write FP32 in hex mem file
# -----------------------------
def write_mem_file(matrix, filename):
    with open(filename, "w") as f:
        for row in matrix:
            for i, val in enumerate(row):
                hex_val = np.float32(val).tobytes().hex().upper()
                f.write(hex_val)
                # new line after every 8 datapoints
                if (i + 1) % 8 == 0:
                    f.write("\n")
            # if row length not multiple of 8, end with newline
            if len(row) % 8 != 0:
                f.write("\n")

# -----------------------------
# Write files
# -----------------------------
write_mem_file(Q, OUTPUT_FILES[0])
write_mem_file(K, OUTPUT_FILES[1])
write_mem_file(V, OUTPUT_FILES[2])

print("Done! Files written in directory:", out_dir)
