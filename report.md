# AI-Assisted Memory System Using Online Perceptron-Controlled Prefetching

## 1. Project Overview

This project implements and verifies an **AI-assisted memory system in
Verilog**. The design combines a small RAM and cache hierarchy with a
stride-based memory access predictor and a lightweight online-learning
perceptron. The objective is not to replace conventional memory
addressing with AI, but to use a learned decision mechanism to determine
whether a speculative prefetch proposed by a conventional predictor
should actually be issued.

The implemented system supports three operating modes:

-   **Mode 0 -- No Prefetch:** cache and RAM only.
-   **Mode 1 -- Conventional Prefetch:** every valid stride-predicted
    candidate is admitted when resources are available.
-   **Mode 2 -- ML-Assisted Prefetch:** a perceptron controls admission
    of stride-predicted candidates after an initial bootstrap period.

The final verified functional configuration uses a **64 x 16-bit RAM**,
a **4-entry cache**, a stride predictor with prefetch distance 2, an
8-feature perceptron, and a 4-entry outstanding-prefetch tracker.

------------------------------------------------------------------------

## 2. Design Objective

A conventional prefetcher can reduce memory access latency when the
access pattern is regular, but incorrect prefetches consume memory
bandwidth and can pollute a small cache. The project therefore addresses
the following question:

> Can a lightweight online-learning hardware classifier learn whether
> candidate prefetches are useful and selectively suppress speculative
> memory accesses when prefetching becomes harmful?

The design uses online feedback. A completed prefetch is tracked, and
its original feature vector is retained. If the processor subsequently
demands the prefetched address within the tracking lifetime, the
prefetch is labelled useful. Otherwise it is eventually labelled
useless. This label is fed back to the perceptron to update its weights.

------------------------------------------------------------------------

## 3. System Architecture

The implemented data and learning flow is:

``` text
CPU memory request
       |
       v
   4-entry cache
       |
   miss|                         Access history
       v                              |
   64 x 16 RAM                        v
                                Stride predictor
                                      |
                               Candidate address
                                      |
                                      v
                               Feature generator
                                      |
                                8-bit features
                                      |
                                      v
                                  Perceptron
                                      |
                              Accept / Reject
                                      |
                                      v
                              Prefetch controller
                                      |
                                      v
                                 RAM -> Cache
                                      |
                                      v
                              Prefetch tracker
                                      |
                            Useful / Useless
                                      |
                                      v
                              Online training
```

Demand memory accesses have priority over speculative prefetch accesses
to the shared RAM interface.

------------------------------------------------------------------------

## 4. RTL Modules

### 4.1 Memory

The backing memory stores 64 words of 16 bits in the verified assignment
configuration. It supports synchronous reads and writes and provides a
`data_valid` response signal.

### 4.2 Cache

A four-entry fully associative cache is used in front of RAM. Each entry
stores a valid bit, address tag, and 16-bit data word. Cache replacement
is round-robin. Duplicate fills are prevented by updating an existing
matching address instead of allocating another copy.

The memory system uses write-through behavior: CPU writes update backing
RAM and update the cache if the written address is currently cached.

### 4.3 Stride Candidate Generator

The stride predictor observes CPU read addresses and computes the
difference between consecutive accesses. A candidate is produced when
two consecutive strides match.

The final design uses a **prefetch distance of 2**:

\[ A\_{prefetch}=A\_{current}+2`\times`{=tex}stride \]

The distance was introduced because a next-address prediction did not
leave enough time for the registered prediction, inference, RAM-read,
and cache-fill pipeline to complete before the next CPU demand.

The predictor supports positive and negative strides and suppresses
candidates outside the memory address range.

### 4.4 Feature Generator

Each candidate is represented by eight binary features describing the
current access/prefetch context. The classifier therefore operates on
behavioral information rather than memorizing individual memory
addresses.

Features include information derived from the stride relationship,
recent cache behavior, previous prefetch usefulness, recent prefetch
accuracy, and address locality.

### 4.5 Perceptron

A lightweight hardware perceptron performs binary classification:

``` text
PREFETCH
or
REJECT
```

The classifier contains eight signed weights and a bias. For inference
it computes a signed score from the feature vector. Training is
performed online using the feature vector retained for the corresponding
prefetch and a target:

``` text
target = 1 : useful prefetch
target = 0 : useless prefetch
```

Thus the model changes during execution without offline software
training.

### 4.6 Prefetch Tracker

The final verified tracker supports four outstanding prefetches. Each
entry stores:

-   prefetched address,
-   feature vector that caused the prediction,
-   validity,
-   age.

A prefetch is useful when its address is demanded before timeout.
Otherwise it is labelled useless after the configured demand-access
lifetime.

Only one training event is sent to the perceptron per cycle, avoiding
the need for a separate training-event queue.

### 4.7 AI Memory Top-Level Controller

`ai_memory_top` integrates the cache, RAM, stride predictor, feature
generator, perceptron, prefetch tracking, RAM arbitration, and
performance-event signals.

The controller implements three modes:

``` text
Mode 0: No prefetching
Mode 1: Conventional stride prefetching
Mode 2: Perceptron-controlled stride prefetching
```

For Mode 2, the first eight eligible candidates are admitted as a
bootstrap period so that the online learner can collect initial positive
and negative examples. Subsequent candidates are admitted or rejected
according to the learned perceptron decision.

------------------------------------------------------------------------

## 5. Verification Methodology

Individual modules were tested independently before integration. Tests
included:

-   RAM read/write operation.
-   Cache miss, fill, hit, replacement, and write-through update.
-   Positive stride prediction.
-   Negative stride prediction.
-   Pattern-break detection.
-   Memory-boundary checking.
-   Perceptron inference and training.
-   Useful-prefetch classification.
-   Useless-prefetch timeout.
-   Boundary case where the target is demanded on the eighth access.
-   Multiple outstanding prefetch tracking.
-   Integrated prediction, prefetch, cache-fill, feedback, and
    online-learning behavior.

The integrated `tb_ai_memory_top.v` test initializes RAM and applies a
sequential read stream.

------------------------------------------------------------------------

## 6. Integrated Functional Verification Result

The verified sequential integration run produced:

``` text
========================================
SEQUENTIAL AI MEMORY TEST
========================================
READ addr=0  data=1000
READ addr=1  data=1001
READ addr=2  data=1002
...
READ addr=15 data=100f

========================================
RESULTS
========================================
Cache hits       = 5
Cache misses     = 11
Prefetch starts  = 8
Useful prefetch  = 3
Useless prefetch = 1
Bootstrap count  = 8
========================================
```

All sixteen returned data values were correct. The simulation also
showed the ML score changing during execution, demonstrating that
feedback reached the perceptron and modified its learned state.

The integrated waveform demonstrates the complete closed loop:

``` text
Repeated stride
      |
      v
Candidate generated
      |
      v
Feature vector
      |
      v
Perceptron / bootstrap admission
      |
      v
Speculative RAM read
      |
      v
Cache fill
      |
      v
Later CPU demand
      |
      v
Cache hit
      |
      v
Useful feedback
      |
      v
Perceptron training
```

This verifies that the AI block is functionally involved in the memory
optimization path rather than being an isolated demonstration module.

------------------------------------------------------------------------

## 7. Comparative Benchmark

A reusable benchmark was run with 128 demand reads per workload in each
of the three operating modes. Five deterministic workloads were used:

1.  Sequential
2.  Fixed stride +2
3.  Reverse sequential
4.  Mixed locality
5.  Irregular

### 7.1 Summary

  ----------------------------------------------------------------------------
  Workload     Mode             Hit Rate Avg.            Throughput  Total RAM
                                         Latency      (reads/cycle)      Reads
                                         (cycles)                   
  ------------ -------------- ---------- ---------- --------------- ----------
  Sequential   No Prefetch         0.00% 5.000             0.139738        128

  Sequential   Conventional       41.41% 4.672             0.155907        164

  Sequential   ML-Assisted        41.41% 4.672             0.155907        164

  Stride +2    No Prefetch         0.00% 5.000             0.139738        128

  Stride +2    Conventional       32.03% 4.859             0.149358        168

  Stride +2    ML-Assisted        33.59% 4.750             0.152200        162

  Reverse      No Prefetch         0.00% 5.000             0.139738        128

  Reverse      Conventional       43.75% 4.594             0.158416        156

  Reverse      ML-Assisted        43.75% 4.594             0.158416        156

  Mixed        No Prefetch         0.00% 5.000             0.139738        128

  Mixed        Conventional        0.00% 5.562             0.129555        176

  Mixed        ML-Assisted         0.00% 5.094             0.137931        136

  Irregular    No Prefetch         0.00% 5.000             0.139738        128

  Irregular    Conventional        0.00% 5.000             0.139738        128

  Irregular    ML-Assisted         0.00% 5.000             0.139738        128
  ----------------------------------------------------------------------------

All benchmark configurations completed with zero data errors in the
verified 64 x 16 configuration.

------------------------------------------------------------------------

## 8. Analysis

### 8.1 Sequential Access

For sequential traffic, conventional and ML-assisted prefetching
produced identical results:

``` text
53 cache hits
75 cache misses
41.41% hit rate
4.672-cycle average latency
0.155907 reads/cycle
89 prefetches
```

After the eight-entry bootstrap, the ML system accepted 81 candidates
and rejected none.

This is desirable behavior: the conventional predictor is useful for a
stable sequential pattern, so the learned controller does not
unnecessarily suppress it.

Relative to no prefetching, average latency decreased from 5.000 to
4.672 cycles and throughput increased from 0.139738 to 0.155907
reads/cycle, at the cost of additional speculative RAM traffic.

### 8.2 Fixed Stride +2

The ML-assisted system slightly outperformed conventional prefetching:

  Metric                Conventional   ML-Assisted
  ------------------- -------------- -------------
  Cache hits                      41            43
  Hit rate                    32.03%        33.59%
  Average latency              4.859         4.750
  Throughput                0.149358      0.152200
  Prefetches                      81            77
  Useful prefetches               41            43
  Prefetch accuracy           53.25%        58.90%
  Total RAM reads                168           162

The ML controller accepted 69 post-bootstrap candidates and rejected 6.
It therefore achieved slightly more useful cache behavior while issuing
fewer speculative accesses.

### 8.3 Reverse Access

Both prefetching modes achieved:

``` text
56 hits
43.75% hit rate
4.594-cycle average latency
0.158416 reads/cycle
```

The ML system accepted all 76 post-bootstrap candidates. This
demonstrates that the learned admission mechanism can preserve useful
negative-stride behavior.

### 8.4 Mixed Access

The mixed workload demonstrates the main motivation for adaptive
control.

No prefetching produced:

``` text
Average latency = 5.000 cycles
RAM reads       = 128
```

Conventional prefetching produced:

``` text
Average latency = 5.562 cycles
RAM reads       = 176
Prefetches      = 48
Accuracy        = 15.91%
```

Thus aggressive conventional prefetching was harmful for this workload.

The ML-assisted system produced:

``` text
Average latency = 5.094 cycles
RAM reads       = 136
Prefetches      = 8
ML accepts      = 0
ML rejects      = 40
```

After bootstrap, the perceptron learned to reject the remaining
candidate prefetches.

Compared with the conventional prefetcher, total RAM traffic fell from
176 to 136 accesses, a reduction of approximately **22.7%**. Average
latency fell from 5.562 to 5.094 cycles, an improvement of approximately
**8.4%**, while throughput increased from 0.129555 to 0.137931
reads/cycle.

The ML system did not completely match the no-prefetch baseline because
the eight bootstrap prefetches still occurred before the model had
sufficient feedback.

### 8.5 Irregular Access

No stable repeated stride was detected in the irregular workload.
Consequently neither prefetching configuration issued speculative
accesses, and all three modes behaved identically.

This illustrates an important architectural boundary: the perceptron
controls candidates generated by the stride predictor; it does not
itself predict arbitrary future memory addresses.

------------------------------------------------------------------------

## 9. What the AI Component Achieves

The project should not be interpreted as a neural network replacing the
memory controller or directly predicting arbitrary addresses.

Its contribution is **adaptive prefetch admission**.

Observed behavior can be summarized as:

``` text
Stable useful pattern
        |
        v
positive feedback
        |
        v
ML continues accepting prefetches


Partially useful pattern
        |
        v
mixed feedback
        |
        v
ML selectively rejects candidates


Poor prefetching pattern
        |
        v
negative feedback
        |
        v
ML suppresses speculative traffic
```

The strongest experimental result is therefore not that ML universally
reduces latency. Instead, the online learner prevents a conventional
stride predictor from continuing harmful speculation when its
predictions become unreliable.

------------------------------------------------------------------------

## 10. FPGA Synthesis and Implementation Results

The verified 64 x 16 design was synthesized in Vivado for all three
prefetch policies using the same FPGA target and a 10 ns (100 MHz) clock
constraint. The complete ML-assisted configuration was then placed and
routed to verify implementation feasibility and obtain a more realistic
timing and power estimate.

### 10.1 Synthesis Comparison

  -----------------------------------------------------------------------
  Metric                 Mode 0: No            Mode 1:            Mode 2:
                           Prefetch       Conventional        ML-Assisted
  -------------- ------------------ ------------------ ------------------
  Slice LUTs                    882                934                941

  Slice                       1,408              1,505              1,511
  Registers /                                          
  FFs                                                  

  WNS                     +1.541 ns          +1.488 ns          +1.548 ns

  TNS                      0.000 ns           0.000 ns           0.000 ns

  Timing at 100                Pass               Pass               Pass
  MHz                                                  
  -----------------------------------------------------------------------

Relative to Mode 0, the instrumented Mode 2 configuration uses 59
additional LUTs (approximately 6.69%) and 103 additional registers
(approximately 7.32%). Relative to Mode 1, Mode 2 uses 7 additional LUTs
(approximately 0.75%) and 6 additional registers (approximately 0.40%).

These differences must be interpreted carefully. The same top-level
design exposes prediction and ML debug outputs in every mode, so Vivado
retains substantial predictor, feature, tracker, and perceptron logic
even when a mode does not use ML for prefetch admission. Therefore the
Mode 0/1/2 differences are comparisons of the complete instrumented
architecture under different policies; they are not the isolated
physical area cost of adding the perceptron.

### 10.2 ML-Assisted Module-Level Synthesis Utilization

For Mode 2, hierarchical synthesis reported:

  Module                       LUTs     FFs
  -------------------------- ------ -------
  Cache                         117      94
  Feature generator               3       9
  Perceptron                    255      86
  Stride predictor               27      23
  RAM                           409   1,041
  Prefetch tracker              108      84
  Complete `ai_memory_top`      941   1,511

The perceptron is a significant source of combinational logic but is not
the dominant source of registers. The RAM accounts for most of the
sequential storage resources. The 64 x 16 memory contains 1,024 data
bits and the current resettable behavioral RAM style is implemented
largely using FPGA registers/LUT logic rather than a block RAM
primitive. This is an implementation limitation and a clear opportunity
for future optimization.

### 10.3 Post-Implementation Utilization

The complete Mode 2 ML-assisted design was placed and routed
successfully.

  Resource             Used   Available   Approx. Utilization
  ----------------- ------- ----------- ---------------------
  Slice LUTs            928      53,200                 1.74%
  Slice Registers     1,520     106,400                 1.43%
  Slices                494      13,300                 3.71%
  F7 Muxes               16      26,600                \<0.1%
  F8 Muxes                8      13,300                \<0.1%
  Bonded I/O             77         200                 38.5%
  BUFGCTRL                1          32                 3.13%

The post-implementation hierarchical utilization was:

  Module                LUTs   Registers   Slices
  ------------------- ------ ----------- --------
  Cache                  115          94       39
  Feature generator        3           9        7
  Perceptron             252          86       76
  Stride predictor        27          30       15
  RAM                    409       1,041      298
  Prefetch tracker       106          86       51
  Complete system        928       1,520      494

The perceptron accounts for approximately 27.2% of total implemented LUT
usage but only about 5.7% of the registers. The RAM accounts for
approximately 68.5% of all registers.

### 10.4 Post-Implementation Timing

The implemented Mode 2 design met all specified timing constraints at
100 MHz:

  Timing Metric                         Result
  -------------------------------- -----------
  Worst Negative Slack (WNS)         +1.061 ns
  Total Negative Slack (TNS)          0.000 ns
  Worst Hold Slack (WHS)             +0.130 ns
  Total Hold Slack (THS)              0.000 ns
  Worst Pulse Width Slack (WPWS)     +4.500 ns
  Failing endpoints                          0

With a 10 ns target period, the implemented critical-path estimate is
approximately 8.939 ns, corresponding to an approximate timing-derived
frequency of 111.9 MHz. This is a timing estimate rather than a measured
maximum operating frequency. The verified result is that the
placed-and-routed design closes timing at the required 100 MHz clock.

### 10.5 Post-Implementation Power Estimate

Vivado's power analysis from the implemented netlist reported:

  Power Metric                  Estimate
  ---------------------- ---------------
  Total on-chip power            0.113 W
  Dynamic power             0.008 W (7%)
  Device static power      0.104 W (93%)
  Clock dynamic power            0.003 W
  Signal dynamic power           0.002 W
  Logic dynamic power            0.002 W
  I/O dynamic power              0.001 W
  Junction temperature            26.3 C
  Ambient temperature             25.0 C
  Thermal margin                  58.7 C

The report marked the power estimate with **low confidence** because
activity was derived from constraints, simulation information, or
vectorless analysis rather than measured workload-specific FPGA
activity. The 0.113 W figure is therefore treated as an
implementation-level estimate, not as measured board power.

Static device power dominates the estimate. Consequently, the reduction
in speculative RAM traffic demonstrated by the ML policy should not be
equated directly with an equal reduction in total FPGA power.

### 10.6 Hardware/Performance Trade-off

The implementation results establish that the complete ML-assisted
system is feasible on the selected FPGA: it occupies less than 2% of
available LUTs and registers and meets the 100 MHz timing requirement
after placement and routing.

The simulation results simultaneously show why the additional control
logic can be useful. In the mixed workload, conventional prefetching
increased total RAM accesses to 176 and average latency to 5.562 cycles.
The ML-assisted policy reduced total RAM accesses to 136 and average
latency to 5.094 cycles by rejecting 40 post-bootstrap candidates.

Thus the demonstrated benefit is not universal speedup. It is the
ability to preserve useful conventional prefetching on regular workloads
while suppressing harmful speculative traffic when runtime feedback
indicates that the predictor should not be trusted.

## 11. Scalability and Scope

The RTL modules were parameterized for configurable address width, data
width, cache entries, tracker entries, prefetch lifetime, prefetch
distance, and feature width. Regression testing at the verified 64 x 16
configuration reproduced the original functional and benchmark results.

A larger-memory validation was explored during development but was not
completed to the same verification standard as the 64 x 16 system. It is
therefore not included in the reported performance results. The
submitted conclusions are restricted to the fully verified 64 x 16
implementation.

The architectural concept is intended to be parameterizable, but this
work does not claim demonstrated generalization to arbitrary memory
capacities or real application workloads.

## 12. Limitations

The current implementation has several explicit limitations:

1.  **Stride-based candidate generation.**\
    The ML classifier can only accept or reject addresses proposed by
    the stride predictor. Pointer chasing and arbitrary correlations are
    outside the present predictor.

2.  **Synthetic workloads.**\
    Evaluation uses deterministic synthetic traces rather than traces
    from complete software applications.

3.  **Small verified memory hierarchy.**\
    Final verified results use a 64 x 16 RAM and four-entry cache.

4.  **Bootstrap overhead.**\
    The first eight eligible ML candidates are forced to prefetch so the
    learner can obtain training examples.

5.  **Simple perceptron.**\
    The classifier is intentionally lightweight and does not represent a
    large neural network.

6.  **No demonstrated total-power reduction.**\
    Reduced speculative RAM traffic does not automatically imply lower
    total FPGA power.

7.  **Prefetch usefulness and realized cache hits differ.**\
    A predicted address can later be demanded and therefore be
    semantically useful while its prefetched cache entry has already
    been evicted.

These limitations define the scope of the conclusions rather than being
hidden from the evaluation.

------------------------------------------------------------------------

## 13. Future Work

Possible extensions include:

-   completing and validating the parameterized 1024-word configuration;
-   evaluating long phase-changing workloads without resetting learned
    weights;
-   using real program memory traces;
-   comparing against a confidence-based adaptive heuristic in addition
    to an always-prefetch stride baseline;
-   increasing cache and tracker capacity;
-   adding correlation or delta-based candidate generators;
-   dynamically adapting prefetch distance;
-   synthesizing all three modes and comparing LUT, FF, BRAM, timing,
    and power;
-   improving BRAM inference by using an FPGA-oriented memory
    implementation;
-   replacing the fixed bootstrap count with a more adaptive exploration
    policy.

------------------------------------------------------------------------

## 14. Conclusion

A complete AI-assisted memory-prefetching prototype was implemented in
Verilog, verified in simulation, synthesized, and successfully placed
and routed on the selected FPGA. The design combines a cache and RAM
hierarchy with stride-based candidate generation, feature extraction, an
online-learning perceptron, speculative prefetch control, and
feedback-based training.

The experiments show that conventional prefetching is effective on
regular access patterns but can become harmful on changing patterns
because of unnecessary memory traffic. The ML-assisted controller
preserves useful prefetch behavior on sequential and reverse patterns,
slightly improves the fixed-stride case, and strongly suppresses harmful
speculative accesses in the mixed workload. In that mixed case, total
RAM traffic was reduced from 176 to 136 accesses and average latency
from 5.562 to 5.094 cycles relative to conventional prefetching.

The final placed-and-routed ML-assisted implementation used 928 LUTs,
1,520 registers, and 494 slices, while meeting the 100 MHz timing
constraint with +1.061 ns worst setup slack and zero failing endpoints.
Vivado estimated 0.113 W total on-chip power for the implemented
netlist, although the estimate was reported with low confidence and is
therefore not treated as measured workload power.

The main contribution is **adaptive online control of a conventional
hardware prefetcher**, rather than universal address prediction or
universal performance improvement. The design demonstrates that a
lightweight learned hardware policy can use runtime feedback to preserve
useful speculation and suppress harmful speculation without offline
retraining.

The results also identify clear limitations: the candidate generator is
stride-based, the verified memory hierarchy is small, the workloads are
synthetic, the behavioral RAM implementation consumes substantial
register resources, and total power savings have not been experimentally
established. These limitations define appropriate future work rather
than changing the verified conclusion of the project.
