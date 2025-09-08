#!/bin/bash
set -euo pipefail

# Install SageAttention at runtime when GPUs are available
echo "Checking and installing SageAttention if needed..."
if ! python3 -c "import sageattention" 2>/dev/null; then
    echo "Installing SageAttention from source..."
    export CUDA_HOME=/usr/local/cuda
    export PATH=$CUDA_HOME/bin:$PATH
    export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH
    export EXT_PARALLEL=4
    export NVCC_APPEND_FLAGS="--threads 8"
    export MAX_JOBS=32
    
    git clone https://github.com/thu-ml/SageAttention.git /tmp/sageattention
    cd /tmp/sageattention
    python setup.py install
    cd /
    rm -rf /tmp/sageattention
    echo "SageAttention installed successfully!"
else
    echo "SageAttention already installed."
fi

echo "running init_extensions.sh"
/usr/local/bin/init_extensions.sh "$@"

echo "running init_models.sh"
/usr/local/bin/init_models.sh "$@"

echo "running the server"
exec "$@"
