# ComfyUI Docker with CUDA support - Optimized for faster builds
FROM nvidia/cuda:12.8.1-devel-ubuntu24.04 AS base

LABEL maintainer="ComfyUI Docker Maintainer"
LABEL version="1.0"
LABEL description="ComfyUI Docker with CUDA and pre-loaded models"

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    COMFYUI_DIR=/app/ComfyUI \
    PATH="/venv/bin:$PATH" \
    LD_LIBRARY_PATH="/usr/local/cuda/lib64:$LD_LIBRARY_PATH" \
    HF_HUB_ENABLE_HF_TRANSFER=1

# Install system dependencies - grouped by category and alphabetized
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build tools and version control
    git \
    git-lfs \
    ninja-build \
    cmake \
    # Python
    python3.12 \
    python3.12-dev \
    python3.12-venv \
    # Libraries for GUI and media
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    # Fonts
    fontconfig \
    fonts-dejavu-core \
    fonts-liberation \
    # Utilities
    curl \
    wget \
    && fc-cache -f -v \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create directories with proper ownership
RUN mkdir -p /app /venv && \
    chown -R 1000:1000 /app /venv

# Switch to ubuntu user for Python package installation
USER 1000

# Setup virtual environment
RUN python3.12 -m venv /venv

# Install PyTorch and dependencies
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir \
    torch==2.6.0 \
    torchvision \
    torchaudio \
    --index-url https://download.pytorch.org/whl/cu124 && \
    pip install --no-cache-dir -U xformers --index-url https://download.pytorch.org/whl/cu124

RUN git clone https://github.com/TimDettmers/bitsandbytes.git /tmp/bitsandbytes && \
    cd /tmp/bitsandbytes && \
    export CUDA_HOME=/usr/local/cuda && \
    export PATH=$CUDA_HOME/bin:$PATH && \
    export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH && \
    cmake -B build -DCOMPUTE_BACKEND=cuda -DCMAKE_CUDA_COMPILER=$CUDA_HOME/bin/nvcc . && \
    cmake --build build -j$(nproc) && \
    cp bitsandbytes/libbitsandbytes_cuda128.so bitsandbytes/libbitsandbytes_cuda124.so && \
    pip install . && \
    cd / && rm -rf /tmp/bitsandbytes

# Clone ComfyUI
WORKDIR /app
RUN git clone https://github.com/comfyanonymous/ComfyUI ${COMFYUI_DIR}
WORKDIR ${COMFYUI_DIR}

# Checkout to last known stable tag
RUN git fetch --tags && \
git checkout $(git describe --tags `git rev-list --tags --max-count=1`)

RUN /venv/bin/python3 -m pip install --no-cache-dir -r ${COMFYUI_DIR}/requirements.txt

# Create required directories and __init__.py file
RUN mkdir -p ${COMFYUI_DIR}/models \
    ${COMFYUI_DIR}/input \
    ${COMFYUI_DIR}/output \
    ${COMFYUI_DIR}/custom_nodes/.last_commits && \
    touch ${COMFYUI_DIR}/custom_nodes/.last_commits/__init__.py

# Install requirements
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir \
    # Additional dependencies
    huggingface_hub \
    hf-transfer \
    pyyaml \
    triton \
    facexlib \
    imageio \
    opencv-python \
    opencv-python-headless \
    pillow \
    scikit-image \
    onnxruntime \
    onnxruntime-gpu \
    streamdiffusion \
    git+https://github.com/rodjjo/filterpy.git

# This is a separate stage for the init scripts
# Changes to these scripts won't invalidate the previous cache
FROM base

# Switch back to root for system operations
USER root

# Copy script files
COPY init_scripts/config.sh \
     init_scripts/init_models.sh \
     init_scripts/init_extensions.sh \
     init_scripts/entrypoint.sh \
     /usr/local/bin/

# Convert CRLF to LF for all copied shell scripts
RUN sed -i 's/\r$//' /usr/local/bin/config.sh && \
    sed -i 's/\r$//' /usr/local/bin/init_models.sh && \
    sed -i 's/\r$//' /usr/local/bin/init_extensions.sh && \
    sed -i 's/\r$//' /usr/local/bin/entrypoint.sh

    
# Make scripts executable
RUN chmod +x /usr/local/bin/config.sh \
    /usr/local/bin/init_models.sh \
    /usr/local/bin/init_extensions.sh \
    /usr/local/bin/entrypoint.sh

# Copy configuration files
COPY --chown=1000:1000 extensions.conf models.conf /app/

# Switch back to ubuntu user for running the application
USER 1000

# Persistent storage configuration
VOLUME ["/app/ComfyUI/models", "/app/ComfyUI/output", "/app/ComfyUI/input", "/app/ComfyUI/custom_nodes"]
VOLUME ["/venv"]

EXPOSE 8188

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ["python3", "main.py", "--listen", "--port", "8188", "--enable-cors-header", "*", "--lowvram", "--async-offload", "--multi-user"]
