#ifndef SensorBridge_h
#define SensorBridge_h

#include <stdbool.h>

#define MSC_MAX_FANS 4

typedef struct {
    bool temperatureAvailable;
    double averageTemperature;
    double hottestTemperature;
    double gpuTemperature;
    int fanStatus;
    int fanCount;
    double fanRPM[MSC_MAX_FANS];
} MSCSensorSnapshot;

bool MSCReadSensorSnapshot(MSCSensorSnapshot *snapshot);

#endif
