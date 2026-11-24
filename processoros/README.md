# ProcessorOS development prototype

Four independently configured ports per machine; shared external input/output, exclusive work inventories. No ME Bridge or recipe pipeline.

Run /processoros/setup.lua to configure 3 machines; then /processoros/main.lua. Feed starts paused; touch row 2 to enable. In-place processing observes item ID/NBT; use batch size 1. Separate input/output mode requires dedicated, initially empty work buffers and a physically configured deterministic machine. Do not share work inventories across computers. No automatic migration of in-flight SmelterOS jobs. This development version has not been validated in Minecraft. Inspect uncertain transfers manually; do not clear journal blindly.

Legacy SmelterOS files remain untouched.
