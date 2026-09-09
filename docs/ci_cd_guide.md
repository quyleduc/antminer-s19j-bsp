# CI/CD & Automation Guide — Antminer S19J BSP

This repository includes a production-grade **GitHub Actions CI/CD Pipeline** (`.github/workflows/build-images.yml`) that automatically validates code quality, builds both **Buildroot 2025.02** and **Debian 12 (Bookworm)** images, and publishes release artifacts.

---

## 🏗️ Pipeline Architecture & Quality Gates

```
Pull Request / Push / Tag
           │
           ▼
┌────────────────────────────────────────┐
│      QUALITY GATE: Static Analysis     │
│  - ShellCheck on scripts/*.sh          │
│  - Python compilation & flake8 lint    │
│  - Defconfig & DTS validation          │
└──────────────────┬─────────────────────┘
                   │ pass
         ┌─────────┴─────────┐
         ▼                   ▼
┌──────────────────┐  ┌──────────────────┐
│ BUILD: Buildroot │  │ BUILD: Debian 12 │
│ - Linux 6.6.58   │  │ - Debootstrap    │
│ - DTB Blob       │  │ - QEMU armhf     │
│ - Buildroot FS   │  │ - Systemd / apt  │
│ - sdcard.img.xz  │  │ - sdcard.img.xz  │
└────────┬─────────┘  └────────┬─────────┘
         │                     │
         └─────────┬───────────┘
                   │ (If Git Tag 'v*')
                   ▼
┌────────────────────────────────────────┐
│     AUTOMATED GITHUB RELEASE ASSETS    │
│  - antminer-s19j-buildroot-sdcard.xz   │
│  - antminer-s19j-debian12-sdcard.xz    │
│  - zImage & am335x-antminer.dtb        │
│  - SHA256SUMS.txt                      │
└────────────────────────────────────────┘
```

---

## ⚡ Pipeline Triggers

1. **Push to `main` or `feature/**`**:
   - Runs validation quality gates and builds images to catch regression early.

2. **Pull Requests against `main`**:
   - Runs full quality gates and build verification before merging.

3. **Manual Trigger (`workflow_dispatch`)**:
   - In GitHub Actions UI, select **Run workflow** with options:
     - `all` (Builds both Buildroot and Debian)
     - `buildroot` (Builds Buildroot only)
     - `debian` (Builds Debian only)

4. **Git Release Tags (`v*`)**:
   - Pushing a version tag (e.g. `git tag v1.0.0 && git push origin v1.0.0`) automatically publishes a GitHub Release with pre-compressed `.img.xz` disk images and SHA256 checksums.

---

## 📦 Artifacts Output by CI

| Artifact Name | Content |
|---|---|
| `antminer-s19j-buildroot-image` | High-compression XZ disk image (`antminer-s19j-buildroot-sdcard.img.xz`) + SHA256 sums |
| `antminer-s19j-debian12-image` | High-compression XZ disk image (`antminer-s19j-debian12-sdcard.img.xz`) + SHA256 sums |
| `antminer-s19j-kernel-and-dtb` | Standalone Linux 6.6 `zImage`, `am335x-antminer.dtb`, and `uEnv.txt` |

---

## 🚀 How to Create a New Release

```bash
# Tag a release version
git tag v1.0.0

# Push tag to GitHub
git push origin v1.0.0
```

GitHub Actions will automatically build both operating system images, generate SHA256 checksums, and publish downloadable assets to GitHub Releases!
