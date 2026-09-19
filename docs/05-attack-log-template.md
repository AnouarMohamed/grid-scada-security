# Attack/Defense Run Log

Copy this template for every attack scenario you run against the full
pipeline. Keep every entry — the pattern across runs is what makes the final
write-up compelling.

---

## Run #___

- **Run ID:**
- **UTC start/end:**
- **Git commit:**
- **Environment/account suffix/region:**
- **Operator principal ARN:**
- **Reviewed Terraform plan SHA-256:**
- **Runtime evidence archive SHA-256:**
- **Pre-run scan timestamp/result:**
- **Attack type:** (naive FDIA / stealthy FDIA / DoS flood / MITM-replay / other)
- **Target measurement(s):**
- **Description of the injected falsification:**
- **Input fixture or command SHA-256:**
- **Expected detector and threshold:**

### Result

- **Detected?** yes / no
- **Detection method that caught it (if any):** (IDS rule / anomaly
  detection / SIEM correlation / not detected)
- **Time to detection:**
- **False positives triggered alongside it?**
- **Detector event UTC timestamp/ID:**
- **Telemetry query UTC range/result:**

### Evidence Index

| Evidence ID | UTC timestamp/range | Description | Private filename | SHA-256 |
| --- | --- | --- | --- | --- |
| `E-01` | | Baseline dashboard | | |
| `E-02` | | Attack interval | | |
| `E-03` | | Detector/alert output | | |
| `E-04` | | Sanitized telemetry query | | |
| `E-05` | | AWS runtime archive | | |
| `E-06` | | Zero-task teardown archive | | |

### Grid-side impact if undetected

- What would a grid operator have concluded from the falsified data?
- What decision might have been made incorrectly as a result?

### Notes / follow-up

-

### Completion Checks

- [ ] All timestamps are UTC and fall inside the evidence window.
- [ ] Every private artifact has a SHA-256 value and controlled storage path.
- [ ] No password, token, cookie, authorization header, or secret value is present.
- [ ] ECS desired/running tasks returned to zero and target health was captured.
- [ ] Lab secrets and temporary access material were rotated or deleted.
- [ ] Billing and budget status were reviewed after teardown.
