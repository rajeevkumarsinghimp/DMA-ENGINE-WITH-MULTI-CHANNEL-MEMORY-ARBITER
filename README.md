📦 Parameterizable DMA Engine + Multi-Channel Arbiter (Synthesizable RTL)

This repository contains a modular, synthesizable RTL design for a scatter–gather DMA engine with multiple channels and a shared AXI4 master interface. The design is split into clean modules for clarity and reusability.

✨ Features

Multi-channel support (NUM_CH parameterizable).

Scatter–gather transfers with descriptor chains.

Round-robin arbiter for fair channel access to a single AXI master.

AXI4 master interface (burst reads/writes).

AXI4-Lite register interface for control/status.

Interrupt controller with per-channel IRQ aggregation.

Performance counters for monitoring transfer stats.

FIFO + CDC utilities for safe data/control crossings.

Clean, synthesizable RTL (no $display, no sim-only code).

📂 Module Breakdown

dma_top.v — Top-level glue, integrates channels, arbiter, reg_if, IRQ, and AXI master.

dma_reg_if.v — AXI-Lite slave, per-channel control/status registers.

dma_channel.v — Per-channel DMA engine (descriptor fetch + transfer FSM).

desc_fetcher.v — Fetches descriptors over AXI.

arbiter.v — Round-robin arbitration of channel requests.

axi_master.v — Simplified AXI4 master skeleton (optional).

interrupt_ctrl.v — IRQ aggregation and masking.

perf_counters.v — Performance monitoring logic.

fifo_sync.v / pulse_sync.v — CDC-safe utility primitives.

🛠️ Assumptions

AXI4 master is simplified (single master, burst-capable, no multi-ID).

Descriptor format is 128-bit, with fields for length, address, and next pointer.

Register map is minimal and easily extensible.

Can be used standalone on FPGA or integrated into SoCs with AXI interconnect.
