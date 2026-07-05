# Workload Verification Tests

Host-PC test files that verify each workload computes the correct answer before
testing on hardware. Each test is a small self-contained C program that prints
the expected 8-bit result (the same value the workload drives onto the
7-segment display).

There is one test per workload:

| Workload | Expected | Test file |
|---|---|---|
| Kalman Steady-State | 0xC7 (199) | `test_kalman_steady_state.c` |
| Bubble Sort | 0xFC (252) | `test_bubble_sort.c` |
| Fibonacci Iterative | 0xC3 (195) | `test_fibonacci_iterative.c` |
| Fibonacci Recursive | 0x62 (98) | `test_fibonacci_recursive.c` |

## Usage

Compile **and run** the test on your machine — compiling alone does not run it.
Pick the line for your shell:

Linux / macOS / WSL / Git Bash (bash, zsh):
```bash
cd workloads/tests
gcc -o test_kalman_steady_state test_kalman_steady_state.c && ./test_kalman_steady_state
```

Windows PowerShell (all versions — older PowerShell has no `&&`):
```powershell
cd workloads\tests
gcc -o test_kalman_steady_state test_kalman_steady_state.c; if ($LASTEXITCODE -eq 0) { .\test_kalman_steady_state }
```

Windows Command Prompt (cmd.exe):
```cmd
cd workloads\tests
gcc -o test_kalman_steady_state test_kalman_steady_state.c && test_kalman_steady_state
```

Run the other tests the same way, substituting the file name. On PowerShell,
prefix the executable with `.\` to run it from the current directory. If GCC is
not found, install it via your platform's package manager (`apt`/`dnf` on Linux,
`brew install gcc` on macOS, MSYS2/MinGW on Windows, or use WSL).

## Workflow

1. **Compile and run the test** on your laptop to get the expected output.
2. **Program the hardware** with the corresponding workload.
3. **Read the 7-segment display** — it must show the same value.
4. If it matches, the hardware computes correctly; if not, investigate.
