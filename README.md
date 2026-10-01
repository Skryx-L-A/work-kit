# Work kit

Offline installer for an Ubuntu x86_64 work laptop. Ask your company's IT which modules and AI services are approved before installing them.

Requirements: Ubuntu 22.04, 24.04 or 26.04; about 15 GB to fetch the offline files and room to install them; network access for the fetch. If Git is unavailable, use GitHub's **Download ZIP** and unpack it to `~/work-kit`.

```sh
git clone https://github.com/Skryx-L-A/work-kit ~/work-kit
bash ~/work-kit/setup/fetch-offline.sh
bash ~/work-kit/setup/install-kit.sh
```

The fetch resumes interrupted downloads and checks SHA-256 hashes. The installer copies and checks the kit, then opens the module menu. Follow [02-laptop-setup.md](02-laptop-setup.md) for the laptop steps.

License: AGPL-3.0-only for original code, including the Agent Workbench (see [LICENSE](LICENSE)); third-party parts keep their own licenses, listed in [NOTICE.md](NOTICE.md).
