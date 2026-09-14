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

\[ A\_{prefetch}=A\_{current}+2`\times `{=tex}stride \]

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

  ----------------------------------------------------------------------------------
  Workload     Mode               Hit Rate Avg. Latency      Throughput    Total RAM
                                               (cycles)   (reads/cycle)        Reads
  ------------ -------------- ------------ ------------ --------------- ------------
  Sequential   No Prefetch           0.00%        5.000        0.139738          128

  Sequential   Conventional         41.41%        4.672        0.155907          164

  Sequential   ML-Assisted          41.41%        4.672        0.155907          164

  Stride +2    No Prefetch           0.00%        5.000        0.139738          128

  Stride +2    Conventional         32.03%        4.859        0.149358          168

  Stride +2    ML-Assisted          33.59%        4.750        0.152200          162

  Reverse      No Prefetch           0.00%        5.000        0.139738          128

  Reverse      Conventional         43.75%        4.594        0.158416          156

  Reverse      ML-Assisted          43.75%        4.594        0.158416          156

  Mixed        No Prefetch           0.00%        5.000        0.139738          128

  Mixed        Conventional          0.00%        5.562        0.129555          176

  Mixed        ML-Assisted           0.00%        5.094        0.137931          136

  Irregular    No Prefetch           0.00%        5.000        0.139738          128

  Irregular    Conventional          0.00%        5.000        0.139738          128

  Irregular    ML-Assisted           0.00%        5.000        0.139738          128
  ----------------------------------------------------------------------------------

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

## 10. Hardware Cost and Power Considerations

The ML-assisted system necessarily introduces additional hardware
compared with the baseline:

-   perceptron weights and bias,
-   score accumulation logic,
-   feature-generation logic,
-   online weight-update logic,
-   prefetch tracking metadata,
-   prediction history,
-   prefetch-control state.

Therefore the ML design is expected to require more FPGA logic resources
and may increase static and internal dynamic power.

The simulation demonstrates reduced **memory traffic** in selected
workloads, particularly the mixed workload, but this alone does not
prove a reduction in total FPGA power. A complete power conclusion
requires synthesis and device-level power analysis.

The correct engineering trade-off is therefore:

\[ `\text{prediction/control hardware overhead}`{=tex}
`\quad `{=tex}`\text{vs.}`{=tex} `\quad`{=tex}
`\text{latency and unnecessary memory-traffic reduction}`{=tex} \]

For this small educational 64-word memory, the fixed control overhead
may be proportionally large. In larger real memory hierarchies,
backing-memory accesses are typically much more expensive relative to
small predictor logic; however, that larger-system energy advantage was
not established by this project and should not be claimed from the
present results.

------------------------------------------------------------------------

## 11. Scalability

The RTL modules were subsequently parameterized for configurable address
width, data width, cache entries, tracker entries, prefetch lifetime,
prefetch distance, and feature width.

The parameterized architecture was regression-tested at the original 64
x 16 configuration and reproduced the verified benchmark behavior.

An attempted 1024 x 16 scalability experiment exposed unresolved
address/data-path issues in the larger test configuration. Therefore the
submitted results are restricted to the verified 64 x 16 configuration.
The larger-memory experiment is considered future work rather than being
reported as a successful result.

This limitation does not invalidate the verified functional design, but
it means the current work does **not** establish generalization to
arbitrary memory capacities or application workloads.

------------------------------------------------------------------------

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
Verilog and verified in simulation. The design combines a cache and RAM
hierarchy with stride-based candidate generation, feature extraction, an
online-learning perceptron, speculative prefetch control, and
feedback-based training.

The experiments show that conventional prefetching is effective on
regular access patterns but can become harmful on changing patterns
because of unnecessary memory traffic. The ML-assisted controller
preserves useful prefetching behavior on sequential and reverse
patterns, slightly improves the fixed-stride case, and strongly
suppresses harmful speculative accesses in the mixed workload.

The main contribution is therefore **adaptive online control of a
conventional hardware prefetcher**, rather than universal address
prediction or universal performance improvement. The design demonstrates
that a lightweight learned hardware policy can use runtime feedback to
change speculative memory behavior without offline retraining.

The verified results support the feasibility of the proposed AI-assisted
decision mechanism while also showing the hardware-overhead,
workload-dependence, and scalability questions that must be considered
in a larger implementation.
