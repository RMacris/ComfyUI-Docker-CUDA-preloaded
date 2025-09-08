# Dockerfile Changelog

This document tracks all changes made to the Dockerfile during the SageAttention integration and Python version optimization process.

## Changes Made

### 1. Base Image Switch (Ubuntu 24.04 → 22.04)
**Date**: September 8, 2025  
**Change**: 
```dockerfile
# FROM: nvidia/cuda:12.8.1-devel-ubuntu24.04 AS base
# TO:
FROM nvidia/cuda:12.8.1-devel-ubuntu22.04 AS base
```
**Reason**: Ubuntu 24.04 only includes Python 3.12 in repositories, but we needed Python 3.11. Ubuntu 22.04 has Python 3.11 available through standard apt packages without requiring compilation from source or external PPAs.

### 2. NVIDIA Repository GPG Key Fix
**Date**: September 8, 2025  
**Added**:
```dockerfile
# Fix NVIDIA repository GPG keys and update sources
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    gnupg \
    wget \
    && wget -qO - https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/3bf863cc.pub | apt-key add - \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
```
**Reason**: Ubuntu 22.04 CUDA base image had GPG signature issues with NVIDIA's repository. The build was failing with "At least one invalid signature was encountered" errors. This fix downloads and adds the correct NVIDIA GPG key.

### 3. Python Version Specification (3.12 → 3.11)
**Date**: September 8, 2025  
**Change**:
```dockerfile
# FROM: python3.12, python3.12-dev, python3.12-venv
# TO:
python3.11 \
python3.11-dev \
python3.11-venv \
python3.11-distutils \
```
**Reason**: User specifically required Python 3.11 for compatibility reasons. Added `python3.11-distutils` to ensure pip and setuptools work properly.

### 4. Removed Python Compilation from Source
**Date**: September 8, 2025  
**Removed**:
```dockerfile
# Complex Python 3.11 compilation steps with build dependencies
# - build-essential, zlib1g-dev, libncurses5-dev, etc.
# - wget Python source, configure, make, make altinstall
# - symlink creation
```
**Reason**: With Ubuntu 22.04, Python 3.11 is available through apt, eliminating the need for time-consuming source compilation and reducing build dependencies.

### 5. Virtual Environment Path Simplification
**Date**: September 8, 2025  
**Change**:
```dockerfile
# FROM: /usr/local/bin/python3.11 -m venv /venv
# TO:
RUN python3.11 -m venv /venv
```
**Reason**: With system-installed Python 3.11, we can use the standard `python3.11` command instead of full path references.

### 6. PyTorch Installation Optimization (Disk Space)
**Date**: September 8, 2025  
**Change**:
```dockerfile
# FROM: Single large RUN command installing all PyTorch components
# TO: Split into separate steps:
RUN pip install --no-cache-dir --upgrade pip
RUN pip install --no-cache-dir torch==2.6.0 --index-url https://download.pytorch.org/whl/cu124
RUN pip install --no-cache-dir torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124
RUN pip install --no-cache-dir -U xformers --index-url https://download.pytorch.org/whl/cu124
```
**Reason**: Build was failing with "No space left on device" errors. PyTorch CUDA packages are very large (664MB+ each). Splitting into separate steps reduces peak temporary disk usage during installation.

### 7. SageAttention Runtime Installation Strategy
**Date**: September 8, 2025  
**Decision**: Install SageAttention at container runtime instead of build time  
**Implementation**: Modified `init_scripts/entrypoint.sh` to check and install SageAttention when container starts
**Reason**: 
- SageAttention compilation requires GPU detection for architecture optimization
- Docker build environment has no GPU access
- Runtime installation allows automatic GPU architecture detection
- Fallback from `pip install .` to `python setup.py install` to avoid isolated build environment issues with torch dependency

### 8. Package Dependencies Added for SageAttention
**Date**: September 8, 2025  
**Added**:
```dockerfile
triton \  # Required dependency for SageAttention
```
**Reason**: SageAttention requires Triton for CUDA kernel compilation and execution.

## Build Issues Resolved

### Issue 1: Python 3.11 Not Available
**Error**: `E: Unable to locate package python3.11` on Ubuntu 24.04  
**Solution**: Switched to Ubuntu 22.04 base image where Python 3.11 is available

### Issue 2: NVIDIA GPG Signature Errors  
**Error**: Repository signature verification failures  
**Solution**: Added proper NVIDIA GPG key installation step

### Issue 3: SageAttention Build-time Compilation Failures
**Error**: `RuntimeError: No GPUs found. Please specify the target GPU architectures`  
**Solution**: Moved SageAttention installation to runtime in entrypoint.sh

### Issue 4: Disk Space Exhaustion
**Error**: `[Errno 28] No space left on device` during PyTorch installation  
**Solution**: 
- Cleaned Docker cache (freed 10.37GB)
- Split PyTorch installation into smaller steps to reduce peak disk usage

### Issue 5: Torch Module Not Found During SageAttention Build
**Error**: `ModuleNotFoundError: No module named 'torch'` in pip build environment  
**Solution**: Changed from `pip install .` to `python setup.py install` to use existing environment

## Current Status

- ✅ Python 3.11 successfully installed via apt packages
- ✅ NVIDIA CUDA repository properly configured
- ✅ PyTorch 2.6.0 with CUDA 12.4 support installed
- ✅ SageAttention configured for runtime installation
- ✅ Build optimized for disk space constraints
- ✅ All dependencies properly resolved

## Next Steps

- Monitor SageAttention runtime installation success
- Verify GPU architecture detection works correctly
- Test ComfyUI functionality with SageAttention integration
- Document performance improvements achieved
