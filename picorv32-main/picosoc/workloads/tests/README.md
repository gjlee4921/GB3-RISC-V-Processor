# Workload Verification Tests

Host PC test files to verify that each workload computes the correct answer before testing on hardware.

## Usage
Compile and run tests on your laptop. Below are platform-specific examples — pick the section that matches your shell.

Note: these tests are simple C programs that print the expected 8-bit result. You must both compile and run the produced executable — compiling alone does not run it.

Linux / macOS (bash, zsh):

```bash
cd workloads/tests

# Compile then run (bash):
gcc -o test_kalman_filter test_kalman_filter.c && ./test_kalman_filter

# Examples for other tests:
gcc -o test_kalman_ss test_kalman_steady_state.c && ./test_kalman_ss
gcc -o test_FIR test_FIR.c && ./test_FIR
```

Windows PowerShell (all versions):

```powershell
cd workloads\tests

# Older PowerShell versions do NOT support '&&'. Use ';' and run the executable explicitly:
gcc -o test_kalman_filter test_kalman_filter.c; if ($LASTEXITCODE -eq 0) { .\test_kalman_filter }

# Or always run regardless of compile status:
gcc -o test_kalman_filter test_kalman_filter.c; .\test_kalman_filter

# Run other tests similarly (note the .\ prefix to execute the binary):
gcc -o test_kalman_ss test_kalman_steady_state.c; if ($LASTEXITCODE -eq 0) { .\test_kalman_ss }
```

Windows Command Prompt (cmd.exe):

```cmd
cd workloads\tests

gcc -o test_kalman_filter test_kalman_filter.c && test_kalman_filter
```

WSL / Git Bash / MSYS2 (bash semantics):

```bash
cd workloads/tests
gcc -o test_kalman_full test_kalman_full.c && ./test_kalman_full
```

Notes:
- On PowerShell you must prefix the executable with `./` or `.\` (for example `.\test_kalman_full`) to run a program in the current directory.
- PowerShell 7+ added `&&`/`||` operators; older PowerShell uses `;` to separate commands. If you want bash-like `&&` on Windows, use WSL, Git Bash or PowerShell 7+.
- If GCC is not found, install it via your platform's package manager: `apt`/`dnf` on Linux, Homebrew on macOS (`brew install gcc`), MSYS2/MinGW on Windows, or use WSL.

## Quick examples (one-liners)

- Linux/macOS / WSL / Git Bash:
	- `gcc -o test_kalman_filter test_kalman_filter.c && ./test_kalman_filter`
- PowerShell (all versions):
	- `gcc -o test_kalman_filter test_kalman_filter.c; if ($LASTEXITCODE -eq 0) { .\test_kalman_filter }`
- Cmd.exe:
	- `gcc -o test_kalman_filter test_kalman_filter.c && test_kalman_filter`


## Expected Results

| Workload | Expected | Test File |
|---|---|---|
| Kalman Steady-State | 0xC7 (199) | test_kalman_steady_state.c |
| Kalman Filter | 0x6C (108) | test_kalman_filter.c |
| FIR | 0x83 (131) | test_FIR.c |
| Bubble Sort | 0xFC (252) | test_bubble_sort.c |
| Fibonacci Iterative | 0xC3 (195) | test_fibonacci_iterative.c |
| Fibonacci Recursive | 0x62 (98) | test_fibonacci_recursive.c |

## Why one test might print immediately and another requires a manual run

- Running `gcc -o kalman_test kalman_test.c; .\kalman_test` both compiles and then runs the produced executable — that will print immediately because you explicitly executed it after compiling.
- If you only ran `gcc -o test_kalman_full test_kalman_full.c;` (ending with a semicolon) then you only compiled the program; the generated executable is not run automatically. To see output you must execute it (e.g. `./test_kalman_full` on bash or `.\test_kalman_full` on PowerShell).

## Workflow

1. **Compile and run the test file** on your laptop to get the expected output (use the OS-specific command above).
2. **Program hardware** with the workload.
3. **Read 7-segment display** — it must show the same value as the test output.
4. If mismatch → computation is wrong. If match → hardware is correct.
