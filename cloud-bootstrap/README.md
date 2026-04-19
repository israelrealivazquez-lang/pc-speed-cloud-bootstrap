# Cloud Bootstrap

PowerShell-first scaffold for moving local work toward cloud storage and remote execution with a safe default posture.

## Goals

- Audit local disk usage without changing anything.
- Prepare Chrome and Edge workflows with explicit, non-destructive steps.
- Plan and execute Google Drive offload only when you opt in.
- Keep remote cloud wrappers small, inspectable, and easy to extend.

## Layout

- `lib/CloudBootstrap.psm1` - shared helpers for logging, dry-run handling, inventory, and path safety.
- `colab/pc_offload_colab_bootstrap.ipynb` - Colab VM bootstrap notebook for Drive-backed remote execution.
- `scripts/Invoke-CloudAudit.ps1` - scan local paths and report offload candidates.
- `scripts/Prepare-ChromeEdge.ps1` - inspect browser presence and print setup guidance.
- `scripts/Invoke-DriveOffload.ps1` - plan or perform a staged copy workflow for Google Drive.
- `scripts/Invoke-CloudRemote.ps1` - generic wrapper for remote command planning and execution.
- `scripts/Invoke-FastRelief.ps1` - apply immediate low-risk relief: npm cache cleanup, Edge policy containment, and OneDrive online-only conversion for selected paths.
- `scripts/Invoke-GcpAlwaysFreeVm.ps1` - create a safe Always Free candidate VM on Google Cloud once billing is active.
- `scripts/Open-ColabBootstrap.ps1` - open the Colab VM bootstrap notebook in Chrome.

## Safety Model

- Dry-run is the default in every script.
- Use `-Commit` to allow the script to perform its real action.
- No script deletes or moves data automatically as part of a default run.
- Path checks block writes outside the requested destination root.

## Quick Start

```powershell
pwsh .\cloud-bootstrap\scripts\Invoke-CloudAudit.ps1
pwsh .\cloud-bootstrap\scripts\Prepare-ChromeEdge.ps1 -ApplyEdgePolicies
pwsh .\cloud-bootstrap\scripts\Invoke-DriveOffload.ps1 -SourcePath "$env:USERPROFILE\Downloads" -Mode Copy
pwsh .\cloud-bootstrap\scripts\Invoke-FastRelief.ps1
pwsh .\cloud-bootstrap\scripts\Invoke-GcpAlwaysFreeVm.ps1 -OpenBillingIfDisabled
pwsh .\cloud-bootstrap\scripts\Open-ColabBootstrap.ps1
pwsh .\cloud-bootstrap\scripts\Invoke-CloudRemote.ps1 -Transport Ssh -HostName cloud-host.example.com -Command 'whoami'
```

## Notes

- This scaffold intentionally avoids Python.
- The first implementation favors observability and safe planning over automation breadth.
- The default Google Drive roots already include the real paths discovered on this machine such as `G:\Mi unidad`, `C:\Users\Lenovo\Streaming de Google Drive\Mi unidad`, and `C:\Users\Lenovo\GoogleDrive_ProjectSpace`.
- Add concrete cloud endpoints, folder mappings, and offload rules as the workflow becomes clearer.

## Colab VM

- The notebook is designed to run in Google Colab with Drive mounted at `/content/drive`.
- It clones or updates this GitHub repository inside the Colab VM so heavy work can run remotely.
- Use it for batch transforms, audits, notebook-style analysis, or any task that should not consume local RAM/CPU.

## GCP Always Free

- The script targets the current project `antigravity-pc1-auto` and the account `israel.realivazquez2811@gmail.com`.
- It stops before creation if billing is disabled, and it can open the billing pages in Chrome to unblock the next run.
- By default it creates an `e2-micro` candidate in `us-central1-a` with a `30 GB` standard boot disk and no external IP, using IAP for SSH access.
