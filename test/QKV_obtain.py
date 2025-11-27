#pip install torch transformers numpy

import torch
import numpy as np
from transformers import AutoTokenizer, AutoModel

# -----------------------------
# Parameters
# -----------------------------
MODEL_NAME = "bert-base-uncased"
SEQ_LEN = 512         # number of tokens = rows
HEAD_IDX = 0          # which attention head to extract
OUTPUT_FILES = ["../mem/Q_32.mem", "../mem/K_32.mem", "../mem/V_32.mem"]

# -----------------------------
# Sample input text (enough to generate 512 tokens)
# -----------------------------
text = " ".join(["Are you sure this is changing??"] * 512)  # repeat so tokenizer produces 512 tokens

# text = "In a distant future, humanity had spread across the stars, establishing colonies on dozens of planets, each with its own culture, challenges, and mysteries. Among these colonies, one planet stood out: Aeloria, a world of floating cities suspended above endless oceans of shimmering, bioluminescent water. The inhabitants of Aeloria were known for their ingenuity, blending advanced technology with a deep respect for nature. The cities were connected by bridges of light that shifted and pulsed like living veins, casting soft glows onto the waves below."

# text += "Every year, the Aelorians celebrated the Festival of the Luminous Tide, a celebration marking the alignment of Aeloria’s three moons. During the festival, citizens released floating lanterns that carried their hopes and dreams, letting them drift into the night sky as the bioluminescent oceans reflected countless shimmering stars. It was a time of joy, reflection, and storytelling. Elder storytellers would recount tales of the early explorers, the first settlers who had braved the cosmic storms to build a new civilization."

# text += "Among the festival-goers was Lira, a young inventor with a curious mind and an insatiable desire for discovery. She spent her days crafting devices that could interact with the tides, capturing energy from the bioluminescent waves and converting it into power for the city. Her latest creation was a small drone, capable of mapping the ocean currents while recording strange, glowing phenomena that no one had yet catalogued."

# text += "One evening, as the moons began their slow dance across the sky, Lira launched her drone over the western ocean cliffs. The device hovered, its sensors scanning the waters below. Suddenly, it detected a pattern, a rhythmic pulse emanating from deep beneath the surface. Intrigued, Lira adjusted the drone’s course, following the mysterious signals as they led toward an uncharted underwater canyon. She marveled at the patterns, their geometry unlike anything she had seen — circles within spirals, moving with an intelligence that suggested something alive."

# text += "The festival’s fireworks erupted above, streaking through the sky in brilliant arcs, but Lira’s attention was elsewhere. Hours passed as she guided the drone deeper into the canyon, recording data and sending it back to her workstation. What she found astonished her: massive, luminescent creatures, far larger than any known aquatic species, moving gracefully in coordinated formations. Their movements synchronized with the tides, creating a living, glowing symphony across the ocean floor."

# text += "Lira realized that this discovery could change everything. These creatures might hold the key to sustainable energy, or perhaps they were remnants of a species thought extinct, hiding in the deep oceans for millennia. She documented every observation meticulously, preparing a report that could bring the world’s attention to Aeloria’s hidden wonders. Her heart raced with the thrill of discovery, knowing that the Festival of the Luminous Tide had brought her to this moment of revelation."

# text += "The next morning, as the suns rose over the floating cities, Lira presented her findings to the council of Aeloria. They were astonished, yet cautious, understanding that such revelations came with great responsibility. Together, they devised plans to study the creatures ethically, ensuring the oceans’ delicate ecosystems remained intact. Lira’s name spread across the colonies as a pioneering scientist, blending curiosity with compassion."

# text += "As the moons continued their eternal dance, and the oceans shimmered beneath floating cities, humanity’s understanding of the universe expanded a little more. The story of Lira and the luminous tides became a legend, inspiring generations to come, reminding them that curiosity, courage, and respect for life could illuminate even the darkest corners of the cosmos. And on Aeloria, the Festival of the Luminous Tide never lost its magic, as citizens watched lanterns drift above glowing oceans, dreaming of what lay beyond the horizon."


# -----------------------------
# Load model
# -----------------------------
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
model = AutoModel.from_pretrained(MODEL_NAME, output_attentions=True)
model.eval()

tokens = tokenizer(text, return_tensors="pt", padding="max_length", truncation=True, max_length=SEQ_LEN)
input_ids = tokens["input_ids"]

# -----------------------------
# Hook to extract Q/K/V
# -----------------------------
qkv_data = {}

def hook(module, input, output):
    # output: tuple (query, key, value)
    # for BERT: output shape = (batch, seq_len, num_heads*head_dim)
    # we need to reshape to (batch, seq_len, num_heads, head_dim)
    q, k, v = output
    qkv_data["Q"] = q.detach()
    qkv_data["K"] = k.detach()
    qkv_data["V"] = v.detach()

# attach hook to the first attention layer of encoder
attn_layer = model.encoder.layer[0].attention.self
# PyTorch BERT returns q, k, v as linear layers before splitting heads
# We'll redefine forward to capture them
def forward_hook_forward(x):
    B, T, H = x.shape[0], x.shape[1], attn_layer.query.out_features
    Q = attn_layer.query(x).view(B, T, attn_layer.num_attention_heads, -1)
    K = attn_layer.key(x).view(B, T, attn_layer.num_attention_heads, -1)
    V = attn_layer.value(x).view(B, T, attn_layer.num_attention_heads, -1)
    return (Q, K, V)

# Forward pass
with torch.no_grad():
    embeddings = model.embeddings(input_ids)
    Q, K, V = forward_hook_forward(embeddings)

# -----------------------------
# Select head 0
# -----------------------------
Q = Q[0, :, HEAD_IDX, :].cpu().numpy()   # shape [512, 64]
K = K[0, :, HEAD_IDX, :].cpu().numpy()
V = V[0, :, HEAD_IDX, :].cpu().numpy()

# [0.0010096, -0.004569, -0.002217, 0.001414, -0.033, -0.028, 0.003, -0.009]
#[-0.279, 0.338, -0.291, -0.312, 0.432, 0.004, 0.760, -0.337]



# -----------------------------
# Helper to write FP32 in hex mem file
# Each row prints 8 datapoints
# -----------------------------
def write_mem_file(matrix, filename):
    with open(filename, "w") as f:
        for row in matrix:
            for i, val in enumerate(row):
                # convert float32 to hex
                hex_val = np.float32(val).tobytes().hex().upper()
                f.write(hex_val)
                if (i+1) % 8 == 0:
                    f.write("\n")  # new row every 8 datapoints
            # handle remaining datapoints if not multiple of 8
            if len(row) % 8 != 0:
                f.write("\n")

# -----------------------------
# Write files
# -----------------------------
write_mem_file(Q, OUTPUT_FILES[0])
write_mem_file(K, OUTPUT_FILES[1])
write_mem_file(V, OUTPUT_FILES[2])

print("Done! Files written:", OUTPUT_FILES)
