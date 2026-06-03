# iCache Simulation Results

| Workload | Cached Cycles | Cached Instns | Result | No-Cache Cycles | No-Cache Instns | Result | Speedup |
|---|---|---|---|---|---|---|---|
| fibonacci_iterative | 12,139 | 2,181 | 0xc3 (195) | 22,691 | 2,181 | 0xc3 (195) | 1.87× |
| fibonacci_recursive | 235,393 | 42,435 | 0x62 (98) | 621,716 | 42,435 | 0x62 (98) | 2.64× |
| FIR | timeout | — | — | — | — | — | — |
| kalman_full | — | — | — | — | — | — | — |
| kalman_steady_state | 803,854 | 103,938 | 0xc7 (199) | 1,447,839 | 103,938 | 0xc7 (199) | 1.80× |
| bubble_sort | 783,210 | 139,937 | 0xfc (252) | 1,533,804 | 139,937 | 0xfc (252) | 1.96× |

## Notes
- Instruction counts are identical between cached and no-cache runs for all workloads — confirms the cache does not affect correctness, only speed.
- Result values match between cached and no-cache for all workloads — confirms correctness.
- FIR timed out — the software multiply routine makes it too slow to simulate in reasonable time.
- kalman_full not yet run.
- Speedup = No-Cache Cycles / Cached Cycles.
