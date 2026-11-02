#pragma once
#include <stdint.h>
int pulse_smc_open(void);
double pulse_temperature(const char *key);
void pulse_smc_close(void);
void pulse_network(uint64_t *received, uint64_t *sent);
