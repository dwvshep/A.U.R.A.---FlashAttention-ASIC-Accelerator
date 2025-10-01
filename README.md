# A.U.R.A.---FlashAttention-ASIC-Accelerator
A.U.R.A. is a SystemVerilog based ASIC accelerator for the FlashAttention kernel used in modern transformers.

### Problem Definition and Motivation
The use of Transformers for various machine learning applications is becoming increasingly common. Their ability to capture more context and use attention to focus on specific parts of the input leads to more accurate and desirable outputs. However, they are computationally expensive, which restricts their use to situations where large amounts of power are readily available. A custom hardware accelerator built to perform the specific calculations required by a Transformer will enable the model to be used in more low power settings.

We will be focusing on machine learning applications on the edge.  These applications require low power and area costs while maintaining high accuracy and performance.  Our project aims to build on previous accelerator architectures and algorithmic advancements to create a new state-of-the-art, open-source, edge accelerator ASIC for the FlashAttention kernel used in modern Transformers. 

### Related Work
A comprehensive breakdown of prior works in this area is detailed in the Appendix.  We have found that most previous implementations for attention accelerators are not tuned for edge devices with tight power and area constraints.  Many designs are FPGA based which impose more overhead for performance, or they use large systolic arrays that do not translate well to smaller architectures.  One architecture, SwiftTron, was specifically developed to target tinyML applications.  However, it was implemented without considerations for FlashAttention and other modern hardware-algorithm co-optimizations such as ExpMul and FLASH-D.

