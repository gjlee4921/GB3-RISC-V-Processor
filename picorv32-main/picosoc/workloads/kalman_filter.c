#include <stdint.h>
#include <stdbool.h>

#ifdef ICEBREAKER
#  define MEM_TOTAL 0x20000
#else
#  error "Set -DICEBREAKER when compiling this C source file"
#endif

extern uint32_t sram;

#define reg_spictrl     (*(volatile uint32_t*)0x02000000)
#define reg_uart_clkdiv (*(volatile uint32_t*)0x02000004)
#define reg_uart_data   (*(volatile uint32_t*)0x02000008)
#define reg_leds        (*(volatile uint8_t*)0x03000000)
#define reg_7seg        (*(volatile uint8_t*)0x03000004)

extern uint32_t flashio_worker_begin;
extern uint32_t flashio_worker_end;

void flashio(uint8_t* data, int len, uint8_t wrencmd) {
	uint32_t func[&flashio_worker_end - &flashio_worker_begin];
	uint32_t* src_ptr = &flashio_worker_begin;
	uint32_t* dst_ptr = func;
	while (src_ptr != &flashio_worker_end)
		*(dst_ptr++) = *(src_ptr++);
	((void(*)(uint8_t*, uint32_t, uint32_t))func)(data, len, wrencmd);
}

void set_flash_qspi_flag() {
	uint8_t buffer[8];
	buffer[0] = 0x35; buffer[1] = 0x00;
	flashio(buffer, 2, 0);
	uint8_t sr2 = buffer[1];
	buffer[0] = 0x31; buffer[1] = sr2 | 2;
	flashio(buffer, 2, 0x50);
}
void set_flash_mode_qddr() { reg_spictrl = (reg_spictrl & ~0x007f0000) | 0x00670000; }

void putchar(char c) { if (c == '\n') putchar('\r'); reg_uart_data = c; }
void print(const char* p) { while (*p) putchar(*(p++)); }
void print_hex(uint32_t v, int digits) {
	for (int i = 7; i >= 0; i--) {
		char c = "0123456789abcdef"[(v >> (4*i)) & 15];
		if (c == '0' && i >= digits) continue;
		putchar(c); digits = i;
	}
}

void setup_picosoc(void) {
	reg_uart_clkdiv = 104; reg_leds = 0x00;
	set_flash_qspi_flag(); set_flash_mode_qddr();
}

// --------------------------------------------------------

#define N   4          // state dimension
#define M   2          // observation dimension
#define STEPS 100
#define QS    8        // fixed-point fractional bits (Q8)
#define ONE   (1 << QS) // 1.0 in Q8 = 256

// Q8 fixed-point multiply (64-bit intermediate to avoid overflow)
static int32_t fmul(int32_t a, int32_t b) {
    return (int32_t)(((int64_t)a * (int64_t)b) >> QS);
}

// Q8 fixed-point divide: returns a / b in Q8
static int32_t fdiv(int32_t a, int32_t b) {
    return (int32_t)((((int64_t)a) << QS) / (int64_t)b);
}

// State-transition matrix F (constant-velocity model, dt = 1)
static const int32_t F[N][N] = {
    {ONE,   0, ONE,   0},
    {  0, ONE,   0, ONE},
    {  0,   0, ONE,   0},
    {  0,   0,   0, ONE},
};

// Observation matrix H (measures px, py)
static const int32_t H[M][N] = {
    {ONE,   0,   0,   0},
    {  0, ONE,   0,   0},
};

// Process noise covariance Q (small) and measurement noise covariance R
static const int32_t Qm[N][N] = {
    {ONE/4,     0,     0,     0},
    {    0, ONE/4,     0,     0},
    {    0,     0, ONE/4,     0},
    {    0,     0,     0, ONE/4},
};
static const int32_t Rm[M][M] = {
    {4*ONE,     0},
    {    0, 4*ONE},
};

// Measurement advance (true velocity) and a 16-entry noise cycle, Q8
static const int32_t z_step[M]     = {2*ONE, 1*ONE};
static const int32_t z_noise[16][M] = {
    { 48,  16}, {-48, -16}, { 32,  64}, {-32, -64},
    { 80, -32}, {-80,  32}, { 16, -48}, {-16,  48},
    { 64,   0}, {-64,   0}, { 32,  48}, {-32, -48},
    {  0,  32}, { 16, -16}, {-16,  16}, {  0, -32},
};

unsigned char run_workload(void) {
    int i, j, k, t;

    // State and covariance (mutable -> SRAM)
    int32_t x[N] = {0, 0, 2*ONE, 1*ONE};
    int32_t z[M] = {-16, 16};
    int32_t P[N][N];

    // Initial covariance: large diagonal (high initial uncertainty)
    for (i = 0; i < N; i++)
        for (j = 0; j < N; j++)
            P[i][j] = (i == j) ? (1000 * ONE) : 0;

    for (t = 0; t < STEPS; t++) {
        // Advance the (noisy) measurement
        z[0] += z_step[0] + z_noise[t & 15][0];
        z[1] += z_step[1] + z_noise[t & 15][1];

        // 1. Predict state: xp = F x
        int32_t xp[N];
        for (i = 0; i < N; i++) {
            int32_t acc = 0;
            for (j = 0; j < N; j++) acc += fmul(F[i][j], x[j]);
            xp[i] = acc;
        }

        // 2. Predict covariance: P = F P F^T + Q
        int32_t FP[N][N];
        for (i = 0; i < N; i++)
            for (j = 0; j < N; j++) {
                int32_t acc = 0;
                for (k = 0; k < N; k++) acc += fmul(F[i][k], P[k][j]);
                FP[i][j] = acc;
            }
        for (i = 0; i < N; i++)
            for (j = 0; j < N; j++) {
                int32_t acc = 0;
                for (k = 0; k < N; k++) acc += fmul(FP[i][k], F[j][k]); // FP * F^T
                P[i][j] = acc + Qm[i][j];
            }

        // 3. Innovation: y = z - H xp
        int32_t y[M];
        for (i = 0; i < M; i++) {
            int32_t acc = 0;
            for (j = 0; j < N; j++) acc += fmul(H[i][j], xp[j]);
            y[i] = z[i] - acc;
        }

        // 4. Innovation covariance: S = H P H^T + R   (M x M = 2 x 2)
        int32_t HP[M][N];
        for (i = 0; i < M; i++)
            for (j = 0; j < N; j++) {
                int32_t acc = 0;
                for (k = 0; k < N; k++) acc += fmul(H[i][k], P[k][j]);
                HP[i][j] = acc;
            }
        int32_t S[M][M];
        for (i = 0; i < M; i++)
            for (j = 0; j < M; j++) {
                int32_t acc = 0;
                for (k = 0; k < N; k++) acc += fmul(HP[i][k], H[j][k]); // HP * H^T
                S[i][j] = acc + Rm[i][j];
            }

        // 5a. Invert S (2x2): Sinv = (1/det) [ S11 -S01 ; -S10 S00 ]
        int32_t det = fmul(S[0][0], S[1][1]) - fmul(S[0][1], S[1][0]);
        int32_t Sinv[M][M];
        Sinv[0][0] = fdiv( S[1][1], det);
        Sinv[0][1] = fdiv(-S[0][1], det);
        Sinv[1][0] = fdiv(-S[1][0], det);
        Sinv[1][1] = fdiv( S[0][0], det);

        // 5b. Gain: K = P H^T Sinv   (N x M = 4 x 2)
        int32_t PHt[N][M];
        for (i = 0; i < N; i++)
            for (j = 0; j < M; j++) {
                int32_t acc = 0;
                for (k = 0; k < N; k++) acc += fmul(P[i][k], H[j][k]); // P * H^T
                PHt[i][j] = acc;
            }
        int32_t K[N][M];
        for (i = 0; i < N; i++)
            for (j = 0; j < M; j++) {
                int32_t acc = 0;
                for (k = 0; k < M; k++) acc += fmul(PHt[i][k], Sinv[k][j]);
                K[i][j] = acc;
            }

        // 6. Update state: x = xp + K y
        for (i = 0; i < N; i++) {
            int32_t acc = xp[i];
            for (j = 0; j < M; j++) acc += fmul(K[i][j], y[j]);
            x[i] = acc;
        }

        // 7. Update covariance: P = (I - K H) P
        int32_t KH[N][N];
        for (i = 0; i < N; i++)
            for (j = 0; j < N; j++) {
                int32_t acc = 0;
                for (k = 0; k < M; k++) acc += fmul(K[i][k], H[k][j]);
                KH[i][j] = (i == j ? ONE : 0) - acc; // (I - K H)
            }
        int32_t Pn[N][N];
        for (i = 0; i < N; i++)
            for (j = 0; j < N; j++) {
                int32_t acc = 0;
                for (k = 0; k < N; k++) acc += fmul(KH[i][k], P[k][j]);
                Pn[i][j] = acc;
            }
        for (i = 0; i < N; i++)
            for (j = 0; j < N; j++)
                P[i][j] = Pn[i][j];
    }

    return (unsigned char)((x[0] >> QS) & 0xFF);
}

void main(void) {
	setup_picosoc();
	unsigned char leds_value = 0x20;
	while (1) { reg_7seg = run_workload(); reg_leds = leds_value; leds_value ^= 0x20; }
}
