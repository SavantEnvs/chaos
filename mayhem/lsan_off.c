/* Build-time LeakSanitizer off-switch for the fuzz build only (linked into /mayhem/chaos).
 * chaos is an allocate-and-exit batch interpreter: it makes no attempt to free interpreter
 * state on exit, so end-of-process leak reports would flood every run with non-actionable
 * "defects" (SPEC §6 item 15). Only leak detection is affected; ASan's memory-safety checks
 * and UBSan stay fully enabled, and no runtime sanitizer option is set by the harness. */
int __lsan_is_turned_off(void) { return 1; }
