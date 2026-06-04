/*
 * test_kalman_steady_state.c — Host PC verification
 * Expected result: 0xC7 (199 decimal)
 *
 * Compile: gcc test_kalman_steady_state.c -o test_kalman_ss && ./test_kalman_ss
 */

#include <stdint.h>
#include <stdio.h>

#define KF_N_STATE  4
#define KF_N_OBS    2
#define KF_N_STEPS  100
#define KF_QSCALE   4

static const int32_t kf_F[KF_N_STATE][KF_N_STATE] = {
    {16,  0, 16,  0},
    { 0, 16,  0, 16},
    { 0,  0, 16,  0},
    { 0,  0,  0, 16},
};

static const int32_t kf_H[KF_N_OBS][KF_N_STATE] = {
    {16,  0,  0,  0},
    { 0, 16,  0,  0},
};

static const int32_t kf_K[KF_N_STATE][KF_N_OBS] = {
    { 8,  0},
    { 0,  8},
    { 4,  0},
    { 0,  4},
};

static const int32_t kf_z_step[KF_N_OBS] = {32, 16};

static const int32_t kf_z_noise[16][KF_N_OBS] = {
    { 3,  1}, {-3, -1}, { 2,  4}, {-2, -4},
    { 5, -2}, {-5,  2}, { 1, -3}, {-1,  3},
    { 4,  0}, {-4,  0}, { 2,  3}, {-2, -3},
    { 0,  2}, { 1, -1}, {-1,  1}, { 0, -2},
};

unsigned char run_workload(void) {
    int32_t x[KF_N_STATE] = {0, 0, 32, 16};
    int32_t z[KF_N_OBS]   = {-3, 1};

    for (int t = 0; t < KF_N_STEPS; t++) {
        z[0] += kf_z_step[0] + kf_z_noise[t & 15][0];
        z[1] += kf_z_step[1] + kf_z_noise[t & 15][1];

        int32_t x_pred[KF_N_STATE];
        for (int i = 0; i < KF_N_STATE; i++) {
            int32_t acc = 0;
            for (int j = 0; j < KF_N_STATE; j++)
                acc += kf_F[i][j] * x[j];
            x_pred[i] = acc >> KF_QSCALE;
        }

        int32_t innov[KF_N_OBS];
        for (int i = 0; i < KF_N_OBS; i++) {
            int32_t hx = 0;
            for (int j = 0; j < KF_N_STATE; j++)
                hx += kf_H[i][j] * x_pred[j];
            innov[i] = z[i] - (hx >> KF_QSCALE);
        }

        for (int i = 0; i < KF_N_STATE; i++) {
            int32_t ki = 0;
            for (int j = 0; j < KF_N_OBS; j++)
                ki += kf_K[i][j] * innov[j];
            x[i] = x_pred[i] + (ki >> KF_QSCALE);
        }
    }

    return (unsigned char)((x[0] >> KF_QSCALE) & 0xFF);
}

int main(void) {
    unsigned char result = run_workload();
    printf("Kalman Steady-State: 0x%02X (%d decimal)\n", result, result);
    return 0;
}
