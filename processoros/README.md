# ProcessorOS development prototype

Install on a fresh CC:T computer (development branch only):

```lua
wget run https://raw.githubusercontent.com/F000NKKK/ProcessorOS/processoros-dev/processor-install.lua
```

Startup is automatic. Stop with Ctrl+T, run /processoros/setup.lua, then reboot. Choose master or slave and identical network group on every computer. Master may also control its own machines, or have zero machines. Connect computers via a wired modem network; the master dashboard collects one-second read-only telemetry and marks missing nodes OFFLINE after five seconds. Slaves work without a monitor and without master. No remote machine commands or remote update in this prototype.

Monitor row 2 toggles local feed, row 3 requests/cancels local update; last row pages the dashboard. Terminal keys p/u/n/b offer the same controls. Update pauses feeding, drains observed work inventories and waits ten quiet seconds, then installs the development branch and reboots. Confirm separate-port machines have no hidden in-flight items before updating; the generic interface cannot observe internal processing. Feed remains paused after update.

Four ports per machine. External input/output may be shared, working inventories must be exclusive. In-place mode observes ID/NBT change; use batch size 1. Separate-port mode requires dedicated initially empty buffers. Do not share working inventories across computers. No automatic migration of in-flight SmelterOS jobs. Do not install over a working SmelterOS computer before draining and stopping it. Legacy files remain untouched, but the startup entry changes.

Development prototype: not validated in Minecraft. Inspect uncertain transfers manually; never clear journals blindly.
