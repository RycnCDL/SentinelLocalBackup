# LinkedIn Post -- SentinelLocalBackup v1.0

Auditors don't want a portal login. They want a file they can open in Excel.

That is the reality I keep running into with German enterprise customers running Microsoft Sentinel. BSI Grundschutz, KRITIS, DSGVO -- the requirement for locally stored, verifiable copies of security logs is non-negotiable for many organizations.

So I built **SentinelLocalBackup** -- an open-source PowerShell module that exports Log Analytics tables to local CSV files, designed specifically for compliance-driven environments.

What it does:

- **Interactive 6-step wizard** -- authentication through export in one guided session
- **Checkpoint and resume** -- survives network drops and token expiry, picks up exactly where it stopped
- **SHA256 integrity hashing** -- every export is cryptographically verifiable via metadata.json
- **UTF-8 BOM encoding** with sep=, hint -- opens correctly in German-locale Excel, no import wizard
- **Smart table discovery** -- detects table plan tiers and color-codes the selection UI

**Important note on Auxiliary tables**: Tables on the Auxiliary (DataLake) tier cannot be exported via standard KQL or REST API -- this is a platform limitation. The tool detects these tables, warns you, and skips them automatically. For Auxiliary tier data, use Azure Portal Search Jobs.

I wrote a detailed blog post covering the architecture, batching strategy, resume capability, and how to set up automated daily backups:

[LINK TO BLOG POST]

MIT-licensed, available on GitHub:
https://github.com/RycnCDL/SentinelLocalBackup

If you run into edge cases or have ideas for improvements, open an issue on the repo -- I actively respond to every one.

#MicrosoftSentinel #CyberSecurity #Compliance #PowerShell #Azure #LogAnalytics #SIEM #InfoSec
