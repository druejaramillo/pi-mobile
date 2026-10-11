#ifndef PI_TAILSCALE_H
#define PI_TAILSCALE_H

// All calls may block and must stay off the main thread. Handles are process-local.
int PiTailscaleStart(const char *directory);
// Caller must free the returned status JSON. NULL means unavailable, never trusted-empty.
char *PiTailscaleStatus(int node);
int PiTailscaleLogin(int node);
// Caller owns the connected socket on success; -1 means failure. Dial deadline: 15 seconds.
int PiTailscaleDial(int node, const char *numeric_address_and_port);
// Closes only the local node; persisted login survives foreground/background cycles.
void PiTailscaleClose(int node);

#endif
