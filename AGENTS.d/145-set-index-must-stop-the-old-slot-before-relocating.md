## Relocating a tree must stop its servers on the old slot first

The move command runs down while the env still names the old index, because once the registry points at the new one a later down resolves the new slot and orphans the servers on the old ports.
