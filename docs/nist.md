| Control | Family | Implementation |
|---------|--------|----------------|
| AC-2  | Access Control      | IAM Revoke Lambda disables compromised keys |
| AC-6  | Least Privilege     | Separate IAM role per Lambda, scoped actions only |
| CM-7  | Least Functionality | SG Lockdown removes 0.0.0.0/0 ingress rules |
| IR-4  | Incident Handling   | All four Lambdas provide automated incident response |
| SC-7  | Boundary Protection | EC2 Isolate moves instance to zero-ingress quarantine SG |
| SC-28 | Protection at Rest  | S3 Block enforces public access blocks and AES256 encryption |
| SI-3  | Malicious Code      | GuardDuty ML detection (mock-compatible architecture) |
| SI-4  | System Monitoring   | CloudWatch MTTR metrics and alarms |
| AU-2  | Audit Events        | Structured JSON logs, CloudWatch metric filters |
| AU-9  | Audit Protection    | S3 versioning, blocked public access on audit bucket |