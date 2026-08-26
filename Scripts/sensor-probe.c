#include "SensorBridge.h"
#include <stdio.h>

int main(void) {
    MSCSensorSnapshot snapshot;
    bool available = MSCReadSensorSnapshot(&snapshot);
    printf("available=%s\n", available ? "true" : "false");
    printf("temperature_available=%s\n", snapshot.temperatureAvailable ? "true" : "false");
    printf("average_temperature=%.2f\n", snapshot.averageTemperature);
    printf("hottest_temperature=%.2f\n", snapshot.hottestTemperature);
    printf("gpu_temperature=%.2f\n", snapshot.gpuTemperature);
    printf("fan_status=%d\n", snapshot.fanStatus);
    printf("fan_count=%d\n", snapshot.fanCount);
    for (int index = 0; index < snapshot.fanCount && index < MSC_MAX_FANS; index++) {
        printf("fan_%d_rpm=%.0f\n", index, snapshot.fanRPM[index]);
    }
    return available ? 0 : 1;
}
