# Attack/Defense Run Log

## Run #2

- **Date:** 2026-09-10
- **Attack type:** coordinated in-envelope false data injection
- **Target measurement(s):** three-phase voltage/current and real/reactive power
- **Description of the injected falsification:** voltage was shifted by
  `0.012 pu`; current and power were increased coherently by four percent.

### Result

- **Detected?** not by the voltage-envelope detector
- **Detection method:** only `attack-flag-forwarder`, used as ground truth
- **Time to detection:** the threshold detector did not detect the replay
- **False positives:** none observed during the baseline replay

### Grid-side impact if undetected

An operator could see a plausible but biased operating point and make dispatch
or voltage-control decisions from falsified measurements.

### Notes / Follow-up

This replay demonstrates the weakness of static thresholds. It is not yet a
state-estimator-derived, topology-consistent FDIA; that remains future power
systems research.
