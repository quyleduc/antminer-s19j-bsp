# BSP enhancement audit — phase 1

Target: Antminer S19J control board v2.5. This branch is **not hardware-validated**.

## Confirmed from repository source
- Buildroot 2025.02, Linux 6.6.58, ARM Cortex-A8 hard-float.
- Kernel uses an in-tree DTS name `ti/omap/am335x-antminer`.
- Custom DTS inherits BeagleBone Black configuration, disables PRUSS and LCDC, and removes UART0 DMA.
- The build script injects DTS into the extracted kernel tree only if the kernel directory already exists. This does not reliably work for a clean build.
- Prior uEnv boot filenames did not match expected Buildroot kernel/DTB artifact names.
- README advertises an SD card image without a corresponding image generation definition.
- README documents a known default root password. Change credentials before attaching to untrusted networks.

## Priorities
1. Replace manual kernel-tree mutation with a Buildroot-supported kernel patch or external-tree integration, ensuring clean-build DTS inclusion and Kbuild registration.
2. Create a deterministic SD image via genimage and verify partition UUID, boot arguments, and legacy U-Boot compatibility on actual hardware.
3. Remove unconditional Buildroot source modifications and uncontrolled deletion of host build directories.
4. Introduce CI for shell syntax, static validation, Buildroot config, DTS compilation and complete image build.
5. Isolate inherited BBB nodes: verify NAND, MMC, Ethernet PHY, GPIO pinmux and regulators against board evidence before enabling devices.
6. Document UART recovery, NAND backup, PRU abort diagnostics, and hardware test matrix.
7. Secure the image: unique credentials/SSH keys, no default root password, and documented first-boot provisioning.

## Hardware gates
Do not enable PRUSS or modify NAND/SPL/U-Boot until pinout, clocks, power domains and recovery path are confirmed. Keep SD boot non-destructive.

## Validation levels
- Static: source consistency (provided in `scripts/validate.sh`).
- Build: clean Buildroot + kernel + DTB + filesystem.
- Boot: serial log, SD boot, Ethernet, SSH.
- Hardware: each peripheral with pinout and measured evidence.

No successful image build, boot or peripheral test is claimed by this audit.
