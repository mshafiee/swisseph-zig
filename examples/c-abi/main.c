/* Drop-in C consumer: link against libswe like the upstream C library. */
#include "swephexp.h"
#include <stdio.h>
int main(void) {
  double xx[6]; char serr[256];
  swe_set_ephe_path(NULL);
  swe_calc_ut(2451545.0, SE_SUN, SEFLG_SPEED, xx, serr);
  printf("Sun: %.6f\n", xx[0]);
  swe_close();
  return 0;
}
