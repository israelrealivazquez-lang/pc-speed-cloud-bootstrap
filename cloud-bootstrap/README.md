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
- `scripts/Invoke-CloudOffloadHub.ps1` - single status hub for GitHub, Hugging Face, Cloudflare, GCP, and OCI offload lanes.
- `scripts/Invoke-OciA1OffloadVm.ps1` - idempotent Oracle Always Free A1 Flex VM launcher with safe defaults.
- `scripts/Invoke-FastRelief.ps1` - apply immediate low-risk relief: npm cache cleanup, Edge policy containment, and OneDrive online-only conversion for selected paths.
- `scripts/Invoke-GcpAlwaysFreeVm.ps1` - create a safe Always Free candidate VM on Google Cloud once billing is active.
- `scripts/Invoke-PerformanceMode.ps1` - stop extra browser/sync load, clean temp files, run fast relief, and reopen only a minimal Colab lane.
- `scripts/Open-CloudWorkspace.ps1` - open Colab, Drive, and GitHub together in a selected Chrome profile.
- `scripts/Open-CloudWorkspace-2811.ps1` - open the shared cloud workspace in `Profile 6`, intended for `israel.realivazquez2811@gmail.com`.
- `scripts/Open-CloudWorkspace-Gmail.ps1` - open the shared cloud workspace in `Default`, intended for `israel.realivazquez@gmail.com`.
- `scripts/Open-ColabBootstrap.ps1` - open the Colab VM bootstrap notebook in Chrome.
- `scripts/Open-ColabBootstrap-Gmail.ps1` - open the same Colab bootstrap notebook using Chrome `Default`, useful for the `israel.realivazquez@gmail.com` account.

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
pwsh .\cloud-bootstrap\scripts\Invoke-PerformanceMode.ps1 -Commit
pwsh .\cloud-bootstrap\scripts\Invoke-PerformanceMode.ps1 -Commit -OpenColab
pwsh .\cloud-bootstrap\scripts\Invoke-CloudOffloadHub.ps1
pwsh .\cloud-bootstrap\scripts\Invoke-CloudOffloadHub.ps1 -RetryOracle -Commit
pwsh .\cloud-bootstrap\scripts\Invoke-OciA1OffloadVm.ps1 -Commit
pwsh .\cloud-bootstrap\scripts\Invoke-GcpAlwaysFreeVm.ps1 -OpenBillingIfDisabled
pwsh .\cloud-bootstrap\scripts\Open-CloudWorkspace-2811.ps1
pwsh .\cloud-bootstrap\scripts\Open-CloudWorkspace-Gmail.ps1
pwsh .\cloud-bootstrap\scripts\Open-ColabBootstrap.ps1
pwsh .\cloud-bootstrap\scripts\Open-ColabBootstrap-Gmail.ps1
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
- It now scans the mounted Drive for `Antigravity_Cloud_Migration` and the known offload folders, so it tolerates different Google accounts and slightly different Drive layouts.
- If `drive.mount('/content/drive')` fails, stop there. Do not run the remaining cells, because Colab can otherwise create a non-persistent local `/content/drive` folder that only looks like Drive.
- The notebook retries Drive mounting with `force_remount=True` and raises a clear error if `/content/drive/MyDrive` is still missing. The safest recovery is `Runtime > Disconnect and delete runtime`, reload the notebook, then mount with the intended Google account.
- Use `Open-ColabBootstrap.ps1` for the `Profile 6` flow tied to `israel.realivazquez2811@gmail.com`.
- Use `Open-ColabBootstrap-Gmail.ps1` for the `Default` Chrome profile tied to `israel.realivazquez@gmail.com`.
- Use it for batch transforms, audits, notebook-style analysis, or any task that should not consume local RAM/CPU.

## Account Split

- `Default` is the lighter `gmail.com` Google account lane for Colab and Drive browsing.
- `Profile 6` is the `2811@gmail.com` lane already tied to the stronger infra side such as `gcloud`.
- The workspace launchers open the same repo and notebook in both profiles, so each account can keep its own session state while sharing the same GitHub bootstrap source.

## Performance Mode

- `Invoke-PerformanceMode.ps1` is the one-shot local relief path when the machine is already choking on RAM or temp files.
- By default it focuses on cleanup and process reduction; add `-OpenColab` only when you actively want the notebook open.
- It also trims working sets for heavy cloud/dev processes so Windows can reclaim physical RAM without forcibly closing `Antigravity`.

## GCP Always Free

- The script targets the current project `antigravity-pc1-auto` and the account `israel.realivazquez2811@gmail.com`.
- It stops before creation if billing is disabled, and it can open the billing pages in Chrome to unblock the next run.
- By default it creates an `e2-micro` candidate in `us-central1-a` with a `30 GB` standard boot disk and no external IP, using IAP for SSH access.

## Oracle CLI

- OCI CLI is installed and the `DEFAULT` profile is intended for `israel.realivazquez2811@gmail.com`.
- The current home region is `mx-monterrey-1` / `MTY`.
- `Invoke-OciA1OffloadVm.ps1` uses only `VM.Standard.A1.Flex` with `1 OCPU`, `6 GB RAM`, and a `50 GB` boot volume by default.
- If Oracle returns `Out of host capacity` or `TooManyRequests`, wait and retry later. Do not switch this workflow to paid shapes just to make it succeed faster.
- The script is idempotent: it reuses existing `pc-offload-*` network resources and avoids duplicate instances.

## GitHub Actions Offload

- `.github/workflows/cloud-offload-dispatch.yml` can be started manually from GitHub Actions.
- `powershell-smoke` runs parser/smoke checks on GitHub-hosted Windows instead of using local CPU/RAM.
- `repo-inventory` generates a repository file inventory artifact in GitHub-hosted compute.
- This is best for repo-centric tasks. It cannot see personal local files unless they are already committed, uploaded, or synced to a cloud source.

## Hugging Face Jobs

- The Hugging Face MCP is authenticated as `israelrealivazquez2811`.
- Use Hugging Face Jobs for CPU/GPU batch workloads when the account plan/quota allows it.
- Jobs should be submitted through the Hugging Face MCP Jobs tool so tokens stay in plugin-managed secrets instead of local scripts.

## Cloudflare

- Cloudflare is the right future lane for lightweight orchestration, Workers, and R2 object storage.
- Current API calls returned an authentication error, so do not rely on Cloudflare until the API token or plugin auth is repaired.
- Once Cloudflare auth works, prefer R2 for object-style offload and Workers for small coordination endpoints, not heavy VM-style compute.
