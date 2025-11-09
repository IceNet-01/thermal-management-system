#!/usr/bin/env python3
import multiprocessing
import time

def stress_cpu(duration):
    """CPU intensive work"""
    end_time = time.time() + duration
    while time.time() < end_time:
        # CPU intensive calculation
        result = sum(i * i for i in range(100000))

if __name__ == "__main__":
    duration = 15 * 60  # 15 minutes
    cores = multiprocessing.cpu_count()

    print(f"Starting CPU stress test on {cores} cores for {duration/60:.0f} minutes...")

    processes = []
    for i in range(cores):
        p = multiprocessing.Process(target=stress_cpu, args=(duration,))
        p.start()
        processes.append(p)

    for p in processes:
        p.join()

    print("Stress test complete!")
