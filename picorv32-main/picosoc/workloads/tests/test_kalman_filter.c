/*
 * test_kalman_filter.c — Host PC verification
 * Expected result: 0x6C (108 decimal)
 *
 * Compile: gcc test_kalman_filter.c -o test_kalman_filter && ./test_kalman_filter
 */

#include <stdint.h>
#include <stdio.h>

#define N   4
#define M   2
#define STEPS 100
#define QS    8
#define ONE   (1 << QS)

static int32_t fmul(int32_t a, int32_t b) {
    return (int32_t)(((int64_t)a * (int64_t)b) >> QS);
}

static int32_t fdiv(int32_t a, int32_t b) {
    return (int32_t)((((int64_t)a) << QS) / (int64_t)b);
}

static const int32_t F[N][N] = {
    {ONE,   0, ONE,   0},
    {  0, ONE,   0, ONE},
    {  0,   0, ONE,   0},
    {  0,   0,   0, ONE},
};

static const int32_t H[M][N] = {
    {ONE,   0,   0,   0},
    {  0, ONE,   0,   0},
};

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

static const int32_t z_step[M]     = {2*ONE, 1*ONE};
static const int32_t z_noise[16][M] = {
    { 48,  16}, {-48, -16}, { 32,  64}, {-32, -64},
    { 80, -32}, {-80,  32}, { 16, -48}, {-16,  48},
    { 64,   0}, {-64,   0}, { 32,  48}, {-32, -48},
    {  0,  32}, { 16, -16}, {-16,  16}, {  0, -32},
};

unsigned char run_workload(void) {
    int i, j, k, t;
    int32_t x[N] = {0, 0, 2*ONE, 1*ONE};
    int32_t z[M] = {-16, 16};
    int32_t P[N][N];

    for (i = 0; i < N; i++)
        for (j = 0; j < N; j++)
            P[i][j] = (i == j) ? (1000 * ONE) : 0;

    for (t = 0; t < STEPS; t++) {
        z[0] += z_step[0] + z_noise[t & 15][0];
        z[1] += z_step[1] + z_noise[t & 15][1];

        int32_t xp[N];
        for (i = 0; i < N; i++) {
            int32_t acc = 0;
            for (j = 0; j < N; j++) acc += fmul(F[i][j], x[j]);
            xp[i] = acc;
        }

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
                for (k = 0; k < N; k++) acc += fmul(FP[i][k], F[j][k]);
                P[i][j] = acc + Qm[i][j];
            }

        int32_t y[M];
        for (i = 0; i < M; i++) {
            int32_t acc = 0;
            for (j = 0; j < N; j++) acc += fmul(H[i][j], xp[j]);
            y[i] = z[i] - acc;
        }

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
                for (k = 0; k < N; k++) acc += fmul(HP[i][k], H[j][k]);
                S[i][j] = acc + Rm[i][j];
            }

        int32_t det = fmul(S[0][0], S[1][1]) - fmul(S[0][1], S[1][0]);
        int32_t Sinv[M][M];
        Sinv[0][0] = fdiv( S[1][1], det);
        Sinv[0][1] = fdiv(-S[0][1], det);
        Sinv[1][0] = fdiv(-S[1][0], det);
        Sinv[1][1] = fdiv( S[0][0], det);

        int32_t PHt[N][M];
        for (i = 0; i < N; i++)
            for (j = 0; j < M; j++) {
                int32_t acc = 0;
                for (k = 0; k < N; k++) acc += fmul(P[i][k], H[j][k]);
                PHt[i][j] = acc;
            }

        int32_t K[N][M];
        for (i = 0; i < N; i++)
            for (j = 0; j < M; j++) {
                int32_t acc = 0;
                for (k = 0; k < M; k++) acc += fmul(PHt[i][k], Sinv[k][j]);
                K[i][j] = acc;
            }

        for (i = 0; i < N; i++) {
            int32_t acc = xp[i];
            for (j = 0; j < M; j++) acc += fmul(K[i][j], y[j]);
            x[i] = acc;
        }

        int32_t KH[N][N];
        for (i = 0; i < N; i++)
            for (j = 0; j < N; j++) {
                int32_t acc = 0;
                for (k = 0; k < M; k++) acc += fmul(K[i][k], H[k][j]);
                KH[i][j] = (i == j ? ONE : 0) - acc;
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

int main(void) {
    unsigned char result = run_workload();
    printf("Kalman Filter: 0x%02X (%d decimal)\n", result, result);
    return 0;
}
