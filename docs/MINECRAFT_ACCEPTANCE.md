# Minecraft acceptance checklist

This is a hardware acceptance procedure, not a claim that the modpack has been tested. Run on a backed-up test world, with exclusive raw and result buffers and no other automation touching them.

1. Update Master and Slaves. On a Slave, D + Enter generates /processoros/data/diagnostic without moving any resources. Inspect every item/fluid port, read/push capability, and pending journal.
2. Press / Saw: submit 12 identical items; verify at least two machines load concurrently and exactly 12 results return (or the recipe's actual yield).
3. Filling: submit three identical inputs plus exactly three recipes' worth of fluid in a dedicated complete batch; verify equal distribution, correct results, and incompatible leftover fluid blocks rather than mixes.
4. Deployer: submit consumable inputs in separate item buffers; verify the configured reusable tool remains in its hand on a fixed tool route. Test an exhausted tool.
5. Mixer: select BATCH mode, physically route Basin products into a separate item inventory and optional fluid tank. Submit a complete batch of mixed ingredients. Verify no ingredient is returned as a result; compare actual output against the AE2 request. A fluid-only recipe does not require item input/output buffers.
6. Master: open EDIT PORTS, replace a raw tank, verify every binding updates and machine numbers remain. Cancel a second edit and verify it does not persist.
7. Recovery: with test resources, shut down a Slave during loading/unloading, reconnect, and compare exact input/output totals. An ambiguous journal must remain faulted, not replay blindly. Capture D report.
8. Block output, then clear it; pause feed, update and reboot, detach/reconnect a wired device. Verify no new loads during maintenance and no silent configuration deletion.

Record modpack version, Create/AE2/NEP versions, before/after resource counts, controller commit, D report and actual PASS/FAIL. A passing Lua CI is not hardware acceptance.
