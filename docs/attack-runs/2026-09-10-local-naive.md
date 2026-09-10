# Attack/Defense Run Log

## Run #1

- **Date:** 2026-09-10
- **Attack type:** naive false data injection
- **Target measurement(s):** phase-A voltage and current
- **Description of the injected falsification:** phase-A voltage was forced to
  `0.88 pu` and phase-A current was increased by 45 percent.

### Result

- **Detected?** yes
- **Detection method:** `voltage-envelope` and `attack-flag-forwarder`
- **Time to detection:** within one two-second ingestion interval
- **False positives:** none observed during the baseline replay

### Grid-side impact if undetected

An operator could conclude that the feeder had a severe undervoltage and
overcurrent condition, potentially causing unnecessary switching or load
shedding.

### Notes / Follow-up

The result proves the sample-level detection and alert-data path. Network IDS
and external SIEM forwarding are not part of this local run.
