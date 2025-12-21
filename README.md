# NeiroSort: Autonomous Waste Sorting System & Physics Simulation

![C++](https://img.shields.io/badge/C++-17-00599C?style=flat&logo=c%2B%2B&logoColor=white)
![OpenCV](https://img.shields.io/badge/OpenCV-4.x-5C3EE8?style=flat&logo=opencv&logoColor=white)
![YOLOv8](https://img.shields.io/badge/YOLO-v8-FCC624?style=flat&logo=yolo&logoColor=black)
![ViT](https://img.shields.io/badge/Model-Vision%20Transformer-FF6F00?style=flat)
![Status](https://img.shields.io/badge/Status-Master's%20Thesis-B31B1B?style=flat)

> **High-performance C++ inference engine for waste sorting in unstructured environments using Hybrid Ensemble Learning (ViT + CNN) and Synthetic Data.**

---

## 1. Demo & Simulation

### Real-time C++ Inference
*(Detection and classification running at high FPS on CPU using OpenCV DNN module)*
### Physics-Based Simulation (Synthetic Data)
*(Custom physics engine modeling ballistic trajectories for rapid dataset generation and "Sim-to-Real" transfer)*
---

## 2. Key Features

### Robust Perception (The Brain)
* **Hybrid Ensemble:** Combines the speed of **MobileNet/ResNet** with the global attention mechanism of **Vision Transformers (ViT)**.
* **Voting Logic:** Implements a weighted consensus algorithm to eliminate false positives common in single-model architectures.
* **Cascade Optimization:** Uses a lightweight *Region Proposal* heuristic to skip heavy inference on empty frames, boosting performance.

### Simulation & Physics (The Environment)
* **Ballistic Trajectory Calculation:** Models the physics of objects thrown from a conveyor belt (velocity vectors, gravity, air resistance).
* **Synthetic Data Generation:** Solves the "data hunger" problem by training models on simulated physics scenarios before real-world deployment.
* **Closed-Loop Testing:** Automatic calculation of sorting efficiency (Hit/Miss ratio) in accelerated time.

### Engineering (The Code)
* **Pure C++ Implementation:** No heavy Python dependencies in runtime. Optimized for Edge devices / Industrial PCs.
* **Modular Architecture:** Designed to be integrated with **ROS 2** nodes for robotic arm control.

---

## 3. System Architecture

The pipeline consists of three stages:

1.  **Region Proposal (Heuristic):** Fast scan of the frame to find "active zones" (motion/contrast).
2.  **Object Detection (YOLOv8):** Localizes waste objects and crops the Region of Interest (ROI).
3.  **Ensemble Classification:**
    * The crop is fed into 3 parallel networks: `ResNet`, `MobileNet`, `ViT`.
    * Votes are weighted (ViT has higher authority due to attention capabilities).
    * Final decision is made via `Softmax` consensus.

---

## 4. Installation & Usage

### Option A: Download Pre-compiled Demo (Recommended)
You don't need to compile the code to test it.
1.  Go to the **[Releases Page](../../releases)**.
2.  Download the latest ZIP archive (`Graduation_Demo_v1.0.zip`).
3.  Unzip and run `Main.exe`.
    * *Includes all DLLs and pre-trained ONNX models.*

### Option B: Build from Source
**Requirements:**
* Visual Studio 2019/2022 (Windows) or GCC (Linux)
* OpenCV 4.8+ (with DNN module)
* CMake

```bash
git clone [https://github.com/NeiroEvgen/NeiroSort.git](https://github.com/NeiroEvgen/NeiroSort.git)
cd NeiroSort
mkdir build && cd build
cmake ..
make
