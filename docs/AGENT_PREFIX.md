# Read first (round 2 agents)
1. Read /workspace/work/nexora/docs/AGENT_BRIEF.md fully and follow it (APIs, contract, toolchain, quality bar).
2. Round-1 agents ran out of time before finishing. YOU MUST finish: write the required entry/page file FIRST (complete, working, compile-safe), then the rest, then tests. Prefer fewer, complete files over ambitious unfinished ones. Keep moving; do not over-research.
3. Compile check on real Flutter 3.27.1 (CI): run in shell with credentials [{"provider":"github"}] and timeout 120:
   `/workspace/work/nexora_check.sh <yourname> "<regex of your paths>"`
   It prints analyzer errors/warnings + test lines for your files (~3 min; if the shell call is promoted to background, wait for its result). Missing entry/page files of OTHER agents are auto-stubbed in the check copy only. The current tree compiles with 0 errors, so any error shown is yours. Iterate until 0 errors/warnings in your files and your tests pass. Run it at least once before you finish, even if you are running low on time.
4. Existing code you build on was written by earlier agents and already compiles: read it before writing (don't rewrite it unless broken).
5. Only write inside your assigned folders/test files.
